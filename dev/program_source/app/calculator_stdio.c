/*
 * Floating-point calculator — stdio version for local testing.
 *
 * Same core logic as calculator.c but uses standard C I/O instead of UART.
 * Used to verify expected outputs against tb_calculator.sv.
 */

#include <stdio.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>

/* ------------------------------------------------------------------ */
/*  Input buffer and parser state                                      */
/* ------------------------------------------------------------------ */

#define INPUT_MAX 80

static char input_buf[INPUT_MAX];
static int  input_pos;

/* ------------------------------------------------------------------ */
/*  Parser helpers                                                     */
/* ------------------------------------------------------------------ */

static void skip_spaces(void)
{
    while (input_buf[input_pos] == ' ' ||
           input_buf[input_pos] == '\t')
        input_pos++;
}

static char peek(void)
{
    skip_spaces();
    return input_buf[input_pos];
}

static char advance(void)
{
    skip_spaces();
    return input_buf[input_pos++];
}

/* ------------------------------------------------------------------ */
/*  Recursive descent parser                                           */
/*  expr   = term (('+' | '-') term)*                                 */
/*  term   = factor (('*' | '/') factor)*                             */
/*  factor = number | '(' expr ')' | 'sqrt' '(' expr ')' | 'neg' '(' expr ')' */
/* ------------------------------------------------------------------ */

static float parse_expr(void);

static float parse_number(void)
{
    /* Read a floating-point number from input */
    int start = input_pos;

    /* Skip sign */
    if (input_buf[input_pos] == '-' || input_buf[input_pos] == '+')
        input_pos++;

    /* Integer part */
    while (input_buf[input_pos] >= '0' && input_buf[input_pos] <= '9')
        input_pos++;

    /* Fractional part */
    if (input_buf[input_pos] == '.') {
        input_pos++;
        while (input_buf[input_pos] >= '0' && input_buf[input_pos] <= '9')
            input_pos++;
    }

    /* Temporarily null-terminate and convert */
    char saved = input_buf[input_pos];
    input_buf[input_pos] = '\0';
    float val = (float)atof(&input_buf[start]);
    input_buf[input_pos] = saved;

    return val;
}

static float parse_factor(void)
{
    char c = peek();

    /* Parenthesized expression */
    if (c == '(') {
        advance();  /* consume '(' */
        float val = parse_expr();
        advance();  /* consume ')' */
        return val;
    }

    /* sqrt(expr) */
    if (c == 's') {
        if (input_buf[input_pos]   == 's' &&
            input_buf[input_pos+1] == 'q' &&
            input_buf[input_pos+2] == 'r' &&
            input_buf[input_pos+3] == 't') {
            input_pos += 4;  /* consume "sqrt" */
            advance();       /* consume '(' */
            float val = parse_expr();
            advance();       /* consume ')' */
            return sqrtf(val);
        }
    }

    /* neg(expr) */
    if (c == 'n') {
        if (input_buf[input_pos]   == 'n' &&
            input_buf[input_pos+1] == 'e' &&
            input_buf[input_pos+2] == 'g') {
            input_pos += 3;  /* consume "neg" */
            advance();       /* consume '(' */
            float val = parse_expr();
            advance();       /* consume ')' */
            return -val;
        }
    }

    /* Unary minus */
    if (c == '-') {
        advance();
        return -parse_factor();
    }

    /* Number */
    return parse_number();
}

static float parse_term(void)
{
    float val = parse_factor();

    while (1) {
        char c = peek();
        if (c == '*') {
            advance();
            val = val * parse_factor();
        } else if (c == '/') {
            advance();
            float divisor = parse_factor();
            if (divisor == 0.0f) {
                printf("ERR: div by zero\r\n");
                return 0.0f;
            }
            val = val / divisor;
        } else {
            break;
        }
    }

    return val;
}

static float parse_expr(void)
{
    float val = parse_term();

    while (1) {
        char c = peek();
        if (c == '+') {
            advance();
            val = val + parse_term();
        } else if (c == '-') {
            advance();
            val = val - parse_term();
        } else {
            break;
        }
    }

    return val;
}

/* ------------------------------------------------------------------ */
/*  Custom ftoa to match bare-metal version (float precision, not double) */
/* ------------------------------------------------------------------ */

static int my_ftoa(float f, char *buf, int precision)
{
    int pos = 0;

    /* Handle sign */
    if (f < 0.0f && f != f) { /* NaN check - skip for simplicity */ }
    if (f < 0.0f) {
        buf[pos++] = '-';
        f = -f;
    }

    /* Handle zero */
    if (f == 0.0f) {
        buf[pos++] = '0';
        if (precision > 0) {
            buf[pos++] = '.';
            for (int i = 0; i < precision; i++)
                buf[pos++] = '0';
        }
        buf[pos] = '\0';
        return pos;
    }

    /* Integer part */
    char int_buf[12];
    int  int_len = 0;

    if (f >= 1.0f) {
        float fi = f;
        while (fi >= 1.0f) {
            int digit = (int)fi % 10;
            int_buf[int_len++] = '0' + digit;
            fi = fi / 10.0f;
            if (int_len >= 11) break;
        }
        for (int i = int_len - 1; i >= 0; i--)
            buf[pos++] = int_buf[i];
    } else {
        buf[pos++] = '0';
    }

    /* Fractional part */
    if (precision > 0) {
        buf[pos++] = '.';

        float frac = f;
        if (f >= 1.0f) {
            float int_val = 0.0f;
            float place = 1.0f;
            for (int i = 0; i < int_len; i++) {
                int_val = int_val + (int_buf[i] - '0') * place;
                place = place * 10.0f;
            }
            frac = f - int_val;
        }

        for (int i = 0; i < precision; i++) {
            frac = frac * 10.0f;
            int digit = (int)frac;
            if (digit > 9) digit = 9;
            if (digit < 0) digit = 0;
            buf[pos++] = '0' + digit;
            frac = frac - (float)digit;
        }
    }

    buf[pos] = '\0';
    return pos;
}

/* ------------------------------------------------------------------ */
/*  Main — batch mode: run all test expressions and print results      */
/* ------------------------------------------------------------------ */

int main(void)
{
    /* Test expressions from tb_calculator.sv */
    const char *tests[] = {
        "1+2",
        "3*4",
        "10-3",
        "8/2",
        "sqrt(4)",
    };
    int num_tests = 5;

    printf("\r\n=== RISC-V FPU Calculator (stdio version) ===\r\n");

    for (int t = 0; t < num_tests; t++) {
        /* Copy expression into input_buf (mimics gets() behavior) */
        memset(input_buf, 0, INPUT_MAX);
        strncpy(input_buf, tests[t], INPUT_MAX - 1);

        /* Skip empty lines */
        if (input_buf[0] == '\0')
            continue;

        printf("> %s\r\n", input_buf);

        input_pos = 0;
        float result = parse_expr();

        /* Use custom ftoa to match bare-metal output */
        char result_buf[32];
        my_ftoa(result, result_buf, 6);
        printf("= %s\r\n", result_buf);

        /* Also show standard printf for comparison */
        printf("  [std printf: %.6f]\r\n", (double)result);
    }

    /* ---- Now test with embedded '\0' to demonstrate the bug ---- */
    printf("\r\n=== Testing trailing NUL effect ===\r\n");
    printf("Simulating what happens when gets() receives a NUL byte:\r\n");

    /* Simulate: gets() reads NUL as first char, then "3*4" */
    memset(input_buf, 0, INPUT_MAX);
    input_buf[0] = '\0';  /* This is what happens when UART has trailing NUL */
    strncpy(&input_buf[1], "3*4", INPUT_MAX - 2);

    printf("input_buf after NUL+\"3*4\": [0]=0x%02x, [1]='%c', [2]='%c', [3]='%c'\r\n",
           (unsigned char)input_buf[0], input_buf[1], input_buf[2], input_buf[3]);
    printf("input_buf[0] == '\\0'? %s → this line would be SKIPPED by the calculator!\r\n",
           input_buf[0] == '\0' ? "YES" : "NO");

    return 0;
}
