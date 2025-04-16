package main

import "core:fmt"
import "core:strings"

Codegen :: struct {
    ast: [dynamic]Stmnt,
    symtab: SymTab,
    code: strings.Builder,
    indent_level: u8,
}

codegen_init :: proc(ast: [dynamic]Stmnt, symtab: SymTab) -> Codegen {
    return {
        ast = ast,
        symtab = symtab,
        code = strings.builder_make(),
        indent_level = 0,
    }
}

gen_array_type :: proc(self: ^Codegen, array: Type, str: ^strings.Builder) {
    #partial switch subtype in array {
    case Array:
        length, length_alloced := gen_expr(self, subtype.len^)
        defer if length_alloced do delete(length)

        fmt.sbprintf(str, "[%v]", length)
        gen_array_type(self, subtype.type^, str)
    case:
        t, t_alloc := gen_type(self, array)
        defer if t_alloc do delete(t)

        fmt.sbprintf(str, "%v", t)
    }
}

gen_ptr_type :: proc(self: ^Codegen, ptr: Type) -> string {
    #partial switch subtype in ptr {
    case Ptr:
        return fmt.aprintf("*%v%v", "const " if subtype.constant else "", gen_ptr_type(self, subtype.type^))
    case:
        t, _ := gen_type(self, ptr)
        return t
    }
}

gen_type :: proc(self: ^Codegen, t: Type) -> (string, bool) {
    if type_tag_equal(t, Untyped_Int{}) {
        panic("compiler error: should not be converting untyped_int to string")
    }

    #partial switch subtype in t {
    case Array:
        ret := strings.builder_make()
        gen_array_type(self, t, &ret)
        return strings.to_string(ret), true
    case Ptr:
        return gen_ptr_type(self, t), true
    case Char:
        return "u8", false
    }

    for k, v in type_map {
        if type_tag_equal(t, v) {
            return k, false
        }
    }
    return "", false
}


gen_indent :: proc(self: ^Codegen) {
    for i in 0..<self.indent_level {
        fmt.sbprint(&self.code, "    ")
    }
}

gen_block :: proc(self: ^Codegen, block: [dynamic]Stmnt) {
    fmt.sbprintln(&self.code, "{")
    self.indent_level += 1

    for statement in block {
        switch stmnt in statement {
        case Block:
            gen_indent(self)
            gen_block(self, stmnt.body)
            fmt.sbprint(&self.code, "\n")
        case FnDecl:
            gen_fn_decl(self, stmnt)
        case VarDecl:
            gen_var_decl(self, stmnt)
        case ConstDecl:
            gen_const_decl(self, stmnt)
        case VarReassign:
            gen_var_reassign(self, stmnt)
        case Return:
            gen_return(self, stmnt)
        case FnCall:
            call := gen_fn_call(self, stmnt, true)
            defer delete(call)
            fmt.sbprint(&self.code, call)
        case If:
            gen_if(self, stmnt)
        }
    }

    self.indent_level -= 1
    gen_indent(self)
    fmt.sbprint(&self.code, "}")
}

gen_if :: proc(self: ^Codegen, ifs: If) {
    gen_indent(self)
    fmt.sbprint(&self.code, "if (")

    condition, alloced := gen_expr(self, ifs.condition)
    defer if alloced do delete(condition)

    fmt.sbprintf(&self.code, "%v) ", condition)
    gen_block(self, ifs.body)

    fmt.sbprint(&self.code, " else ")
    gen_block(self, ifs.els)
}

gen_fn_decl :: proc(self: ^Codegen, fndecl: FnDecl) {
    gen_indent(self)
    fmt.sbprintf(&self.code, "pub fn %v(", fndecl.name.literal)

    for stmnt, i in fndecl.args {
        arg := stmnt.(ConstDecl)
        arg_str, arg_str_alloced := gen_type(self, arg.type)
        defer if arg_str_alloced do delete(arg_str)

        if i == 0 {
            fmt.sbprintf(&self.code, "%v: %v", arg.name.literal, arg_str)
        } else {
            fmt.sbprintf(&self.code, ", %v: %v", arg.name.literal, arg_str)
        }
    }
    fntype_str, fntype_str_alloced := gen_type(self, fndecl.type)
    defer if fntype_str_alloced do delete(fntype_str)

    fmt.sbprintf(&self.code, ") %v ", fntype_str)

    gen_block(self, fndecl.body)

    // NOTE: this is a hacky solution to make the formating
    // of the output code prettier.
    // NOTE: should i just make it so the output isn't readable?
    strings.pop_byte(&self.code)
    fmt.sbprint(&self.code, "\n}")
}

// returns allocated string, needs to be freed
@(require_results)
gen_fn_call :: proc(self: ^Codegen, fncall: FnCall, with_indent: bool = false) -> string {
    if with_indent {
        gen_indent(self)
    }

    call := strings.builder_make()
    fmt.sbprintf(&call, "%v(", fncall.name.literal)
    for arg, i in fncall.args {
        expr, alloced := gen_expr(self, arg)
        defer if alloced do delete(expr)

        if i == 0 {
            fmt.sbprintf(&call, "%v", expr)
        } else {
            fmt.sbprintf(&call, ", %v", expr)
        }
    }
    fmt.sbprint(&call, ")")

    return strings.to_string(call)
}

// returns string and true if string is allocated
gen_expr :: proc(self: ^Codegen, expression: Expr) -> (string, bool) {
    switch expr in expression {
    case Char:
        // NOTE: for now char -> u8 even tho it's checked as if it were a "rune"
        // TODO: find a way to represent utf8 char in zig
        return "u8", false
    case Bool:
        return "bool", false
    case I8:
        return "i8", false
    case I16:
        return "i16", false
    case I32:
        return "i32", false
    case I64:
        return "i64", false
    case U8:
        return "u8", false
    case U16:
        return "u16", false
    case U32:
        return "u32", false
    case U64:
        return "u64", false
    case F32:
        return "f32", false
    case F64:
        return "f64", false
    case Ident:
        return expr.literal, false
    case IntLit:
        return expr.literal, false
    case FloatLit:
        return expr.literal, false
    case CharLit:
        literal := fmt.aprintf("'%v'", expr.literal)
        return literal, true
    case True:
        return "true", false
    case False:
        return "false", false
    case Deref:
        return "*", false
    case FieldAccess:
        subexpr, subexpr_alloced := gen_expr(self, expr.expr^)
        field, field_alloced := gen_expr(self, expr.field^)
        ret := fmt.aprintf("%v.%v", subexpr, field)

        if subexpr_alloced {
            delete(subexpr)
        }
        if field_alloced {
            delete(field)
        }

        return ret, true
    case Address:
        value, alloced := gen_expr(self, expr.value^)
        ret := fmt.aprintf("&%v", value)
        
        if alloced {
            delete(value)
        }

        return ret, true
    case FnCall:
        return gen_fn_call(self, expr), true
    case Literal:
        literal := strings.builder_make()
        expr_type_str, expr_type_str_alloced := gen_type(self, expr.type)
        defer if expr_type_str_alloced do delete(expr_type_str)

        fmt.sbprintf(&literal, "%v{{", expr_type_str)
        for val, i in expr.values {
            str_val, alloced := gen_expr(self, val)
            defer if alloced do delete(str_val)

            if i == 0 {
                fmt.sbprintf(&literal, "%v", str_val)
            } else {
                fmt.sbprintf(&literal, ", %v", str_val)
            }
        }
        fmt.sbprint(&literal, "}")
        return strings.to_string(literal), true
    case Grouping:
        value, alloced := gen_expr(self, expr.value^)
        ret := fmt.aprintf("(%v)", value)
        if alloced {
            delete(value)
        }

        return ret, true
    case Negative:
        value, alloced := gen_expr(self, expr.value^)
        ret := fmt.aprintf("-%v", value)
        
        if alloced {
            delete(value)
        }

        return ret, true
    case Not:
        cond, alloced := gen_expr(self, expr.condition^)
        ret := fmt.aprintf("!%v", cond)
        
        if alloced {
            delete(cond)
        }

        return ret, true
    case LessThan:
        lhs, lhs_alloc := gen_expr(self, expr.left^)
        rhs, rhs_alloc := gen_expr(self, expr.right^)
        ret := fmt.aprintf("%v < %v", lhs, rhs)

        if lhs_alloc {
            delete(lhs)
        }
        if rhs_alloc {
            delete(rhs)
        }

        return ret, true
    case LessOrEqual:
        lhs, lhs_alloc := gen_expr(self, expr.left^)
        rhs, rhs_alloc := gen_expr(self, expr.right^)
        ret := fmt.aprintf("%v <= %v", lhs, rhs)

        if lhs_alloc {
            delete(lhs)
        }
        if rhs_alloc {
            delete(rhs)
        }

        return ret, true
    case GreaterThan:
        lhs, lhs_alloc := gen_expr(self, expr.left^)
        rhs, rhs_alloc := gen_expr(self, expr.right^)
        ret := fmt.aprintf("%v > %v", lhs, rhs)

        if lhs_alloc {
            delete(lhs)
        }
        if rhs_alloc {
            delete(rhs)
        }

        return ret, true
    case GreaterOrEqual:
        lhs, lhs_alloc := gen_expr(self, expr.left^)
        rhs, rhs_alloc := gen_expr(self, expr.right^)
        ret := fmt.aprintf("%v >= %v", lhs, rhs)

        if lhs_alloc {
            delete(lhs)
        }
        if rhs_alloc {
            delete(rhs)
        }

        return ret, true
    case Equality:
        lhs, lhs_alloc := gen_expr(self, expr.left^)
        rhs, rhs_alloc := gen_expr(self, expr.right^)
        ret := fmt.aprintf("%v == %v", lhs, rhs)

        if lhs_alloc {
            delete(lhs)
        }
        if rhs_alloc {
            delete(rhs)
        }

        return ret, true
    case Inequality:
        lhs, lhs_alloc := gen_expr(self, expr.left^)
        rhs, rhs_alloc := gen_expr(self, expr.right^)
        ret := fmt.aprintf("%v != %v", lhs, rhs)

        if lhs_alloc {
            delete(lhs)
        }
        if rhs_alloc {
            delete(rhs)
        }

        return ret, true
    case Plus:
        lhs, lhs_alloc := gen_expr(self, expr.left^)
        rhs, rhs_alloc := gen_expr(self, expr.right^)
        ret := fmt.aprintf("%v + %v", lhs, rhs)

        if lhs_alloc {
            delete(lhs)
        }
        if rhs_alloc {
            delete(rhs)
        }

        return ret, true
    case Minus:
        lhs, lhs_alloc := gen_expr(self, expr.left^)
        rhs, rhs_alloc := gen_expr(self, expr.right^)
        ret := fmt.aprintf("%v - %v", lhs, rhs)

        if lhs_alloc {
            delete(lhs)
        }
        if rhs_alloc {
            delete(rhs)
        }

        return ret, true
    case Multiply:
        lhs, lhs_alloc := gen_expr(self, expr.left^)
        rhs, rhs_alloc := gen_expr(self, expr.right^)
        ret := fmt.aprintf("%v * %v", lhs, rhs)

        if lhs_alloc {
            delete(lhs)
        }
        if rhs_alloc {
            delete(rhs)
        }

        return ret, true
    case Divide:
        lhs, lhs_alloc := gen_expr(self, expr.left^)
        rhs, rhs_alloc := gen_expr(self, expr.right^)
        ret := fmt.aprintf("%v / %v", lhs, rhs)

        if lhs_alloc {
            delete(lhs)
        }
        if rhs_alloc {
            delete(rhs)
        }

        return ret, true
    }

    unreachable()
}

gen_var_decl :: proc(self: ^Codegen, vardecl: VarDecl) {
    gen_indent(self)
    var_type_str, var_type_str_alloced := gen_type(self, vardecl.type)
    defer if var_type_str_alloced do delete(var_type_str)

    fmt.sbprintf(&self.code, "var %v: %v = ", vardecl.name.literal, var_type_str)

    if vardecl.value == nil {
        fmt.sbprintln(&self.code, "undefined;")
    } else {
        value, alloced := gen_expr(self, vardecl.value)
        defer if alloced do delete(value)
        fmt.sbprintfln(&self.code, "%v;", value)
    }
}

gen_var_reassign :: proc(self: ^Codegen, varre: VarReassign) {
    gen_indent(self)
    reassigned, reassigned_alloced := gen_expr(self, varre.name)
    defer if reassigned_alloced do delete(reassigned)

    value, value_alloced := gen_expr(self, varre.value)
    defer if value_alloced do delete(value)

    fmt.sbprintfln(&self.code, "%v = %v;", reassigned, value)
}

gen_const_decl :: proc(self: ^Codegen, constdecl: ConstDecl) {
    gen_indent(self)
    const_type_str, const_type_str_alloced := gen_type(self, constdecl.type)
    defer if const_type_str_alloced do delete(const_type_str)

    value, alloced := gen_expr(self, constdecl.value)
    defer if alloced do delete(value)

    fmt.sbprintfln(&self.code, "const %v: %v = %v;", constdecl.name.literal, const_type_str, value);
}

gen_return :: proc(self: ^Codegen, ret: Return) {
    gen_indent(self)
    value, alloced := gen_expr(self, ret.value)
    defer if alloced do delete(value)

    fmt.sbprintfln(&self.code, "return %v;", value)
}

gen :: proc(self: ^Codegen) {
    for statement in self.ast {
        #partial switch stmnt in statement {
        case FnDecl:
            gen_fn_decl(self, stmnt)
        case VarDecl:
            gen_var_decl(self, stmnt)
        case ConstDecl:
            gen_const_decl(self, stmnt)
        case VarReassign:
            gen_var_reassign(self, stmnt)
        }
    }
}
