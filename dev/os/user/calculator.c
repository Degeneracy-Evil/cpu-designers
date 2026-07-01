/*
 * Floating-point calculator for SimpleOS user mode (RV32IMF).
 *
 * Ported from dev/program_source/app/calculator.c for U-mode:
 *   - Console I/O via ecall syscalls (user.h) instead of direct UART MMIO.
 *   - No uart_init() — the OS owns UART initialization.
 *   - Adds run_tests() self-check invoked before the interactive loop.
 *
 * Supports:
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

#include "user.h"
#include "math.h"

/* Map original stdio/uart names to syscall-based user library. The
 * original calculator.c called printf/gets/uart_puts; user.h provides
 * user_printf/user_gets/user_puts with identical signatures. */
#define printf     user_printf
#define gets       user_gets
#define uart_puts  user_puts

/* atof is defined in atof.c (copied verbatim from lib/); user.h does
 * not declare it, so provide a forward declaration here. */
float atof(const char *s);

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
/*  Self-check                                                         */
/* ------------------------------------------------------------------ */

/* Load a literal string into the parser input buffer and evaluate it.
 * Mirrors the original run_tests template's eval_expression("...") call
 * pattern, adapted to the global-state recursive-descent parser. */
static float eval_str(const char *s)
{
    int i = 0;
    while (s[i] != '\0' && i < INPUT_MAX - 1) {
        input_buf[i] = s[i];
        i++;
    }
    input_buf[i] = '\0';
    input_pos = 0;
    return parse_expr();
}

void run_tests(void)
{
    int pass = 0, total = 0, first_fail = 0;
    float result;

    /* Test 1: "1+2" = 3.0 */
    total++; result = eval_str("1+2");
    printf("1+2 = ");
    print_float(result, 6);
    printf("\n");
    if (fabsf(result - 3.0f) < 0.0001f) pass++; else if (!first_fail) first_fail = 1;

    /* Test 2: "3*4" = 12.0 */
    total++; result = eval_str("3*4");
    printf("3*4 = ");
    print_float(result, 6);
    printf("\n");
    if (fabsf(result - 12.0f) < 0.0001f) pass++; else if (!first_fail) first_fail = 2;

    /* Test 3: "10-3" = 7.0 */
    total++; result = eval_str("10-3");
    printf("10-3 = ");
    print_float(result, 6);
    printf("\n");
    if (fabsf(result - 7.0f) < 0.0001f) pass++; else if (!first_fail) first_fail = 3;

    /* Test 4: "8/2" = 4.0 */
    total++; result = eval_str("8/2");
    printf("8/2 = ");
    print_float(result, 6);
    printf("\n");
    if (fabsf(result - 4.0f) < 0.0001f) pass++; else if (!first_fail) first_fail = 4;

    /* Test 5: "sqrt(4)" = 2.0 */
    total++; result = eval_str("sqrt(4)");
    printf("sqrt(4) = ");
    print_float(result, 6);
    printf("\n");
    if (fabsf(result - 2.0f) < 0.0001f) pass++; else if (!first_fail) first_fail = 5;

    /* Print results */
    printf("Tests: %d/%d passed\n", pass, total);
    if (first_fail) printf("First failure: test %d\n", first_fail);

    /* Report self-check results to kernel (writes to PA_SELF_CHECK).
     * Unlike sys_exit, sys_report returns — execution continues to the
     * interactive calculator loop below. */
    sys_report(pass, total, first_fail);
}

/* ------------------------------------------------------------------ */
/*  Main                                                               */
/* ------------------------------------------------------------------ */

int main(void)
{
    /* Run self-check tests first, then enter interactive loop.
     * run_tests() calls sys_report() which writes results to memory
     * and returns — execution falls through to the calculator loop. */
    run_tests();

    printf("\n=== RISC-V FPU Calculator ===\n");
    printf("Supports: + - * / () sqrt() neg()\n");
    printf("Type 'exit' to quit.\n\n");

    for (;;) {
        printf("> ");
        gets(input_buf, INPUT_MAX);

        /* Skip empty lines */
        if (input_buf[0] == '\0')
            continue;

        /* Exit command */
        if (input_buf[0] == 'e' &&
            input_buf[1] == 'x' &&
            input_buf[2] == 'i' &&
            input_buf[3] == 't' &&
            input_buf[4] == '\0') {
            sys_exit(0, 0, 0);
        }

        input_pos = 0;
        float result = parse_expr();
        printf("= ");
        print_float(result, 6);
        printf("\n");
    }

    return 0;
}
