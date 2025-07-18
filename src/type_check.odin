package main

import "core:strconv"
import "core:strings"
import "core:fmt"
import "core:math"

I8_MAX  :: max(i8)
I8_MIN  :: min(i8)
I16_MAX :: max(i16)
I16_MIN :: min(i16)
I32_MAX :: max(i32)
I32_MIN :: min(i32)
I64_MAX :: max(i64)
I64_MIN :: min(i64)

U8_MAX  :: max(u8)
U8_MIN  :: min(u8)
U16_MAX :: max(u16)
U16_MIN :: min(u16)
U32_MAX :: max(u32)
U32_MIN :: min(u32)
U64_MAX :: max(u64)
U64_MIN :: min(u64)

USIZE_MAX :: max(int)
USIZE_MIN :: min(int)

ISIZE_MAX :: max(uint)
ISIZE_MIN :: min(uint)

F32_MIN :: min(f32)
F32_MAX :: min(f32)
F64_MIN :: min(f64)
F64_MAX :: min(f64)

tc_is_constant :: proc(type: ^Type) -> ^bool {
    switch &t in type {
    case I8:
        return &t.constant
    case I16:
        return &t.constant
    case I32:
        return &t.constant
    case I64:
        return &t.constant
    case Isize:
        return &t.constant
    case U8:
        return &t.constant
    case U16:
        return &t.constant
    case U32:
        return &t.constant
    case U64:
        return &t.constant
    case Usize:
        return &t.constant
    case F32:
        return &t.constant
    case F64:
        return &t.constant
    case Array:
        return &t.constant
    case Ptr:
        return &t.constant
    case Bool:
        return &t.constant
    case Char:
        return &t.constant
    case Cstring:
        return &t.constant
    case String:
        return &t.constant
    case Option:
        return &t.constant
    case TypeDef:
        return &t.constant
    case Void:
        panic("inside tc_is_constant, can't get constant from void")
    case Untyped_Float:
        panic("inside tc_is_constant, can't get constant from untyped_float")
    case Untyped_Int:
        panic("inside tc_is_constant, can't get constant from untyped_int")
    }

    panic("inside tc_is_constant, type is nil")
}

tc_make_constant :: proc(type: ^Type) {
    switch &t in type {
    case I8, I16, I32, I64, Isize, U8, U16, U32, U64, Usize, F32, F64,
         Bool, Char, String, Cstring:
        tc_is_constant(type)^ = true
        return
    case Array:
        tc_make_constant(t.type)
        tc_is_constant(type)^ = true
        return
    case Ptr:
        // we won't make its underlying type constant
        tc_is_constant(type)^ = true
        return
    case Option:
        tc_make_constant(t.type)
        tc_is_constant(type)^ = true
        return
    case TypeDef:
        t.constant = true
    case Void:
        panic("inside tc_make_constant, can't get constant from void")
    case Untyped_Float:
        panic("inside tc_make_constant, can't get constant from untyped_float")
    case Untyped_Int:
        panic("inside tc_make_constant, can't get constant from untyped_int")
    }

    panic("inside tc_make_constant, type is nil")
}

tc_deref_ptr :: proc(analyser: ^Analyser, type: ^Type) -> ^Type {
    #partial switch &t in type {
    case Ptr:
        return t.type
    case:
        return &t
    }
}

tc_array_equals :: proc(analyser: ^Analyser, lhs: Type, rhs: ^Type) -> bool {
    #partial switch &l in lhs {
    case Array:
        if lhs_len, ok := l.len.?; ok {
            #partial switch r in rhs {
            case Array:
                l_len, _ := evaluate_expr(analyser, lhs_len)
                if _, ok := r.len.?; !ok do elog(analyser, r.cursors_idx, "cannot infer array length")
                r_len, _ := evaluate_expr(analyser, r.len.?)
                if l_len != r_len do return false
                return tc_array_equals(analyser, l.type^, r.type)
            }
        } else {
            #partial switch r in rhs {
            case Array:
                r_len, _ := evaluate_expr(analyser, r.len.?)
                l.len = new(Expr);
                l.len = r.len.?
                return tc_array_equals(analyser, l.type^, r.type)
            }
        }
    case:
        return tc_equals(analyser, lhs, rhs)
    }

    unreachable()
}

tc_ptr_equals :: proc(analyser: ^Analyser, lhs: Type, rhs: ^Type) -> bool {
    #partial switch &l in lhs {
    case Ptr:
        #partial switch r in rhs {
        case Ptr:
            if !l.constant && r.constant do return false
            if !l.constant && !r.constant do return tc_ptr_equals(analyser, l.type^, r.type)
            if l.constant do return tc_ptr_equals(analyser, l.type^, r.type)
        }
    case:
        return tc_equals(analyser, lhs, rhs)
    }

    unreachable()
}

// <ident>: <lhs> = <rhs>
// rhs is a pointer because it might be correct if wrapped in an Option
tc_equals :: proc(analyser: ^Analyser, lhs: Type, rhs: ^Type) -> bool {
    switch l in lhs {
    case Void:
        debug("warning: unexpected comparison between Void and %v", rhs)
    case TypeDef:
        _ = symtab_find(analyser, l.name, l.cursors_idx)
        #partial switch r in rhs {
        case TypeDef:
            if l.name == r.name {
                return true
            }
        }
    case Option:
        #partial switch &r in rhs {
        case Option:
            if type_tag_equal(l.type^, Void{}) || type_tag_equal(r.type^, Void{}) {
                elog(analyser, l.cursors_idx, "cannot use ?void, maybe use a bool instead?")
            }

            if r.is_null {
                r.type^ = l.type^
                r.gen_option = true;
                return true
            }
            return tc_equals(analyser, l.type^, r.type)
        case:
            if tc_equals(analyser, l.type^, rhs) {
                subtype := new(Type); subtype^ = rhs^
                // NOTE: ^ this leaks memory but is needed for the lifetime
                // of the process so it will be cleaned once the process ends
                rhs^ = Option{
                    type = subtype,
                    is_null = false,
                    gen_option = true,
                    cursors_idx = 0,
                }
                return true
            }
            return false
        }
    case Ptr:
        return tc_ptr_equals(analyser, lhs, rhs)
    case Array:
        return tc_array_equals(analyser, lhs, rhs)
    case Untyped_Int:
        #partial switch r in rhs {
        case Untyped_Int, I8, I16, I32, I64, Isize, U8, U16, U32, U64, Usize:
            return true
        }
    case Untyped_Float:
        #partial switch r in rhs {
        case Untyped_Float, F32, F64:
            return true
        }
    case Bool:
        _, ok := rhs.(Bool)
        return ok
    case Char:
        _, ok := rhs.(Char)
        return ok
    case Cstring:
        _, ok := rhs.(Cstring)
        return ok
    case String:
        _, ok := rhs.(String)
        return ok
    case I8:
        #partial switch r in rhs {
        case I8, Untyped_Int:
            rhs^ = l
            return true
        }
    case I16:
        #partial switch r in rhs {
        case Untyped_Int:
            rhs^ = l
            return true
        case I16, I8:
            return true
        }
    case I32:
        #partial switch r in rhs {
        case Untyped_Int:
            rhs^ = l
            return true
        case I32, I16, I8:
            return true
        }
    case I64:
        #partial switch r in rhs {
        case Untyped_Int:
            rhs^ = l
            return true
        case I64, I32, I16, I8:
            return true
        }
    case Isize:
        #partial switch r in rhs {
        case Untyped_Int:
            rhs^ = l
            return true
        case Isize, I64, I32, I16, I8:
            return true
        }
    case U8:
        #partial switch r in rhs {
        case U8, Untyped_Int:
            rhs^ = l
            return true
        }
    case U16:
        #partial switch r in rhs {
        case Untyped_Int:
            rhs^ = l
            return true
        case U16, U8:
            return true
        }
    case U32:
        #partial switch r in rhs {
        case Untyped_Int:
            rhs^ = l
            return true
        case U32, U16, U8:
            return true
        }
    case U64:
        #partial switch r in rhs {
        case Untyped_Int:
            rhs^ = l
            return true
        case U64, U32, U16, U8:
            return true
        }
    case Usize:
        #partial switch r in rhs {
        case Untyped_Int:
            rhs^ = l
            return true
        case Usize, I64, I32, I16, I8:
            return true
        }
    case F32:
        #partial switch r in rhs {
        case F32, Untyped_Float:
            rhs^ = l
            return true
        }
    case F64:
        #partial switch r in rhs {
        case Untyped_Float:
            rhs^ = l
            return true
        case F64, F32:
            return true
        }
    }

    return false
}

tc_return :: proc(analyser: ^Analyser, fn: FnDecl, ret: ^Return) {
    if ret.type == nil {
        ret.type = fn.type // fn.type can't be nil
    }

    if ret.value == nil {
        if type_tag_equal(fn.type, Void{}) {
            return
        }

        elog(analyser, get_cursor_index(cast(Stmnt)ret^), "mismatch types, function type isn't void, expression type is void")
    }

    ret_expr_type := type_of_expr(analyser, &ret.value)

    if !tc_equals(analyser, ret.type, ret_expr_type) {
        elog(analyser, get_cursor_index(cast(Stmnt)ret^), "mismatch types, return type %v, expression type %v", ret.type, ret_expr_type)
    }

    if !tc_equals(analyser, fn.type, &ret.type) {
        elog(analyser, get_cursor_index(cast(Stmnt)ret^), "mismatch types, function type %v, return type %v", fn.type, ret.type)
    }
}

// returns nil if t != untyped
tc_default_untyped_type :: proc(t: Type) -> Type {
    #partial switch _ in t {
    case Untyped_Int:
        return I64{}
    case Untyped_Float:
        return F64{}
    case:
        return nil
    }
}

tc_infer :: proc(analyser: ^Analyser, lhs: ^Type, expr: ^Expr) {
    expr_type := type_of_expr(analyser, expr)
    expr_default_type := tc_default_untyped_type(expr_type^)

    #partial switch t in expr_type^ {
    case TypeDef:
        _ = symtab_find(analyser, t.name, t.cursors_idx)
    }

    if expr_default_type != nil {
        lhs^ = expr_default_type
    } else {
        lhs^ = expr_type^
    }
}

tc_number_within_bounds :: proc(analyser: ^Analyser, type: Type, expression: Expr) {
    #partial switch expr in expression {
    case IntLit:
        #partial switch t in type {
        case F32:
            value := cast(f64)expr.literal
            if cast(f64)expr.literal > auto_cast F32_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in f32", value)
            }
        case F64:
            value := cast(f64)expr.literal
            if value > auto_cast F64_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in f64", value)
            }
        case U8:
            value := expr.literal
            if value > auto_cast U8_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in u8", value)
            }
        case U16:
            value := expr.literal
            if value > auto_cast U16_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in u16", value)
            }
        case U32:
            value := expr.literal
            if value > auto_cast U32_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in u32", value)
            }
        case U64:
            value := expr.literal
            if value > auto_cast U64_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in u64", value)
            }
        case Usize:
            value := expr.literal
            if value > auto_cast U64_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in usize", value)
            }
        case I8:
            value := cast(i64)expr.literal
            if value > auto_cast I8_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in i8", value)
            }
        case I16:
            value := cast(i64)expr.literal
            if value > auto_cast I16_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in i16", value)
            }
        case I32:
            value := cast(i64)expr.literal
            if value > auto_cast I32_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in i32", value)
            }
        case I64:
            value := cast(i64)expr.literal
            if value > auto_cast I64_MAX {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in i64", value)
            }
        case Isize:
            value := cast(i64)expr.literal
            if value > auto_cast ISIZE_MIN {
                elog(analyser, get_cursor_index(expression), "literal \"%v\" cannot be represented in isize", value)
            }
        }
    case Negative:
        #partial switch ex in expr.value^ {
        case IntLit:
            #partial switch t in type {
            case I8:
                value := cast(i64)ex.literal
                if value < auto_cast I8_MIN {
                    elog(analyser, get_cursor_index(expression), "literal \"-%v\" cannot be represented in i8", value)
                }
            case I16:
                value := cast(i64)ex.literal
                if value < auto_cast I16_MIN {
                    elog(analyser, get_cursor_index(expression), "literal \"-%v\" cannot be represented in i16", value)
                }
            case I32:
                value := cast(i64)ex.literal
                if value < auto_cast I32_MIN {
                    elog(analyser, get_cursor_index(expression), "literal \"-%v\" cannot be represented in i32", value)
                }
            case I64:
                value := cast(i64)ex.literal
                if value < auto_cast I64_MIN {
                    elog(analyser, get_cursor_index(expression), "literal \"-%v\" cannot be represented in i64", value)
                }
            case Isize:
                value := cast(i64)ex.literal
                if value < auto_cast ISIZE_MIN {
                    elog(analyser, get_cursor_index(expression), "literal \"-%v\" cannot be represented in isize", value)
                }
            }
        }
    }
}

tc_var_decl :: proc(analyser: ^Analyser, vardecl: ^VarDecl) {
    if vardecl.value == nil {
        // <ident>: <type>;
        if type_tag_equal(vardecl.type, Void{}) {
            // <ident>: void; error
            elog(analyser, vardecl.cursors_idx, "variable cannot be of type void")
        }
    } else if vardecl.type == nil {
        tc_infer(analyser, &vardecl.type, &vardecl.value)
    } else {
        expr_type := type_of_expr(analyser, &vardecl.value)
        if !tc_equals(analyser, vardecl.type, expr_type) {
            elog(analyser, vardecl.cursors_idx, "mismatch types, variable \"%v\" type %v, expression type %v", vardecl.name, vardecl.type, expr_type)
        }
    }

    if arr, ok := vardecl.type.(Array); ok {
        if _, ok := arr.len.?; !ok {
            elog(analyser, vardecl.cursors_idx, "cannot infer array length for \"%v\" without compound literal", vardecl.name.literal)
        }

        return
    }

    tc_number_within_bounds(analyser, vardecl.type, vardecl.value)
}

tc_const_decl :: proc(analyser: ^Analyser, constdecl: ^ConstDecl) {
    expr_type := type_of_expr(analyser, &constdecl.value)

    if constdecl.type == nil {
        tc_infer(analyser, &constdecl.type, &constdecl.value)
    } else if !tc_equals(analyser, constdecl.type, expr_type) {
        elog(analyser, constdecl.cursors_idx, "mismatch types, variable \"%v\" type %v, expression type %v", constdecl.name, constdecl.type, expr_type)
    }
    tc_make_constant(&constdecl.type)

    tc_number_within_bounds(analyser, constdecl.type, constdecl.value)
}

tc_can_compare_value :: proc(analyser: ^Analyser, lhs, rhs: Type) -> bool {
    #partial switch l in lhs {
    case Char:
        return type_tag_equal(rhs, Char{})
    case Bool:
        return type_tag_equal(rhs, Bool{})
    case I8, I16, I32, I64, Isize:
        #partial switch r in rhs {
        case I8, I16, I32, I64, Isize, Untyped_Int:
            return true
        case:
            return false
        }
    case U8, U16, U32, U64, Usize:
        #partial switch r in rhs {
        case U8, U16, U32, U64, Usize, Untyped_Int:
            return true
        case:
            return false
        }
    case Untyped_Int:
        #partial switch r in rhs {
        case Untyped_Int, I8, I16, I32, I64, U8, U16, U32, U64, Isize, Usize:
            return true
        case:
            return false
        }
    case F32, F64, Untyped_Float:
        #partial switch r in rhs {
        case F32, F64, Untyped_Float:
            return true
        case:
            return false
        }
    case:
        return false
    }
}

tc_can_compare_order :: proc(analyser: ^Analyser, lhs, rhs: Type) -> bool {
    #partial switch l in lhs {
    case I8, I16, I32, I64, Isize:
        #partial switch r in rhs {
        case I8, I16, I32, I64, Isize:
            return true
        case:
            return false
        }
    case U8, U16, U32, U64, Usize:
        #partial switch r in rhs {
        case U8, U16, U32, U64, Usize:
            return true
        case:
            return false
        }
    case Untyped_Int:
        #partial switch r in rhs {
        case Untyped_Int, I8, I16, I32, I64, U8, U16, U32, U64, Isize, Usize:
            return true
        case:
            return false
        }
    case F32, F64, Untyped_Float:
        #partial switch r in rhs {
        case F32, F64, Untyped_Float:
            return true
        case:
            return false
        }
    case:
        return false
    }
}

tc_is_unsigned :: proc(analyser: ^Analyser, expr: Expr) -> bool {
    expr := expr
    type := type_of_expr(analyser, &expr)

    #partial switch t in type {
    case U8, U16, U32, U64, Usize:
        return true
    case I8, I16, I32, I64, Isize:
        return false
    case:
        elog(analyser, get_cursor_index(expr), "expected an integer type, got %v", type)
    }
}
