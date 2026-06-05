/*
 * Floating-point calculator for SimpleCPU (RV32IMF).
 *
 * UART-based interactive calculator supporting:
 *   +  addition       3.14+2.86
 *   -  subtraction    10-3.5
 *   *  multiplication 2.5*4
 *   /  division       10/3
 *   () parentheses    (1+2)*3
 *   sqrt()            sqrt(2)
 *   neg()             neg(3.14)
 *
 * Uses recursive descent parser for expression evaluation.
 */

#include "stdio.h"
#include "math.h"

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
    float val = atof(&input_buf[start]);
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
                uart_puts("ERR: div by zero\r\n");
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
/*  Main                                                               */
/* ------------------------------------------------------------------ */

int main(void)
{
    uart_init(UART_BAUD_115200);

    uart_puts("\r\n=== RISC-V FPU Calculator ===\r\n");
    uart_puts("Supports: + - * / () sqrt() neg()\r\n");
    uart_puts("Example: (1+2)*3.5\r\n\r\n");

    for (;;) {
        uart_puts("> ");
        gets(input_buf, INPUT_MAX);

        /* Skip empty lines */
        if (input_buf[0] == '\0')
            continue;

        input_pos = 0;
        float result = parse_expr();
        uart_puts("= ");
        print_float(result, 6);
        uart_puts("\r\n");
    }

    return 0;
}
