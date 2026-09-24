#include <lean/lean.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern void lean_initialize_runtime_module(void);
extern lean_object *initialize_Init_System_IO(uint8_t builtin);
extern lean_object *initialize_LambdaCalculus_App_Wasm(uint8_t builtin);
extern lean_object *stlc_process(lean_object *source, uint32_t fuel, uint8_t check_only);

int stlc_init(void) {
    lean_initialize_runtime_module();
    lean_object *result = initialize_Init_System_IO(1);
    if (lean_io_result_is_error(result)) {
        lean_dec(result);
        return 1;
    }
    lean_dec(result);
    result = initialize_LambdaCalculus_App_Wasm(1);
    if (lean_io_result_is_error(result)) {
        lean_io_result_show_error(result);
        lean_dec(result);
        return 1;
    }
    lean_dec(result);
    lean_io_mark_end_initialization();
    return 0;
}

/* The caller owns the returned UTF-8 buffer and releases it with free. */
char *stlc_request(const char *source, uint32_t length, uint32_t fuel, uint8_t check_only) {
    lean_object *result = stlc_process(lean_mk_string_from_bytes(source, length), fuel, check_only);
    size_t size = lean_string_size(result);
    char *output = malloc(size);
    if (output) memcpy(output, lean_string_cstr(result), size);
    lean_dec(result);
    return output;
}
