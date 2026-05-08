/* Generated config.h for mes-on-mes build via M2-Planet.
 *
 * mes/src/mes.c references MES_VERSION as `make_string0 (MES_VERSION)`,
 * which requires MES_VERSION to expand to a C string literal. Defining
 * it via `-D MES_VERSION=...` on the kaem command line drops the embedded
 * quotes, so the macro expands to bare tokens like 0.27.1 — M2-Planet
 * silently emits 0 and mes faults dereferencing NULL. Define the string
 * here where the quotes are unambiguous.
 */
#define MES_VERSION "0.27.1"
