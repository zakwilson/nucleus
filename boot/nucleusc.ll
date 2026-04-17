; ModuleID = 'src/nucleusc.nuc'
source_filename = "src/nucleusc.nuc"
target triple = "x86_64-pc-linux-gnu"

%StructDef = type { ptr, ptr, ptr, i32 }

%Type = type { i32, ptr, ptr, i32, i32, ptr, ptr }

%Tok = type { i32, i32, i64, ptr }

%Node = type { i32, i32, i64, ptr, ptr, ptr }

%Sym = type { ptr, ptr, ptr, i32, i32, ptr }

%Scope = type { ptr, ptr, i32, i32 }

%StrLit = type { ptr, i32, i32 }

%Val = type { ptr, ptr }

%BinOp = type { ptr, ptr, i32 }

%LibcDecl = type { ptr, ptr, i32, i32, i32, i32, i32, i32, i32 }

%Vec = type { ptr, i32, i32 }

%MacroDef = type { ptr, ptr, i32, i32 }

@.str.0 = private unnamed_addr constant [5 x i8] c"cond\00", align 1
@.str.1 = private unnamed_addr constant [5 x i8] c"true\00", align 1
@.str.2 = private unnamed_addr constant [5 x i8] c"cond\00", align 1
@.str.3 = private unnamed_addr constant [5 x i8] c"cond\00", align 1
@.str.4 = private unnamed_addr constant [4 x i8] c"not\00", align 1
@.str.5 = private unnamed_addr constant [2 x i8] c"=\00", align 1
@.str.6 = private unnamed_addr constant [2 x i8] c"=\00", align 1
@.str.7 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.8 = private unnamed_addr constant [4 x i8] c"let\00", align 1
@.str.9 = private unnamed_addr constant [6 x i8] c"while\00", align 1
@.str.10 = private unnamed_addr constant [2 x i8] c"<\00", align 1
@.str.11 = private unnamed_addr constant [5 x i8] c"inc!\00", align 1
@.str.12 = private unnamed_addr constant [4 x i8] c"let\00", align 1
@.str.13 = private unnamed_addr constant [6 x i8] c"while\00", align 1
@.str.14 = private unnamed_addr constant [2 x i8] c"_\00", align 1
@.str.15 = private unnamed_addr constant [2 x i8] c"_\00", align 1
@.str.16 = private unnamed_addr constant [13 x i8] c"arena malloc\00", align 1
@.str.17 = private unnamed_addr constant [27 x i8] c"nucleusc: arena exhausted\0A\00", align 1
@.str.18 = private unnamed_addr constant [8 x i8] c"__gs_%d\00", align 1
@.str.19 = private unnamed_addr constant [18 x i8] c"%s:%d: error: %s\0A\00", align 1
@.str.20 = private unnamed_addr constant [28 x i8] c"unterminated string literal\00", align 1
@.str.21 = private unnamed_addr constant [19 x i8] c"unknown escape \5C%c\00", align 1
@.str.22 = private unnamed_addr constant [24 x i8] c"string literal too long\00", align 1
@.str.23 = private unnamed_addr constant [25 x i8] c"integer literal too long\00", align 1
@.str.24 = private unnamed_addr constant [13 x i8] c"unexpected )\00", align 1
@.str.25 = private unnamed_addr constant [6 x i8] c"quote\00", align 1
@.str.26 = private unnamed_addr constant [11 x i8] c"quasiquote\00", align 1
@.str.27 = private unnamed_addr constant [8 x i8] c"unquote\00", align 1
@.str.28 = private unnamed_addr constant [15 x i8] c"unquote-splice\00", align 1
@.str.29 = private unnamed_addr constant [24 x i8] c"unexpected end of input\00", align 1
@.str.30 = private unnamed_addr constant [18 x i8] c"unterminated list\00", align 1
@.str.31 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.32 = private unnamed_addr constant [3 x i8] c"i1\00", align 1
@.str.33 = private unnamed_addr constant [3 x i8] c"i8\00", align 1
@.str.34 = private unnamed_addr constant [4 x i8] c"i16\00", align 1
@.str.35 = private unnamed_addr constant [4 x i8] c"i32\00", align 1
@.str.36 = private unnamed_addr constant [4 x i8] c"i64\00", align 1
@.str.37 = private unnamed_addr constant [4 x i8] c"ptr\00", align 1
@.str.38 = private unnamed_addr constant [5 x i8] c"<fn>\00", align 1
@.str.39 = private unnamed_addr constant [5 x i8] c"%%%s\00", align 1
@.str.40 = private unnamed_addr constant [2 x i8] c"?\00", align 1
@.str.41 = private unnamed_addr constant [28 x i8] c"nucleusc: too many structs\0A\00", align 1
@.str.42 = private unnamed_addr constant [4 x i8] c"int\00", align 1
@.str.43 = private unnamed_addr constant [3 x i8] c"i1\00", align 1
@.str.44 = private unnamed_addr constant [3 x i8] c"i8\00", align 1
@.str.45 = private unnamed_addr constant [4 x i8] c"i16\00", align 1
@.str.46 = private unnamed_addr constant [4 x i8] c"i32\00", align 1
@.str.47 = private unnamed_addr constant [4 x i8] c"i64\00", align 1
@.str.48 = private unnamed_addr constant [5 x i8] c"bool\00", align 1
@.str.49 = private unnamed_addr constant [4 x i8] c"ptr\00", align 1
@.str.50 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.51 = private unnamed_addr constant [17 x i8] c"unknown type: %s\00", align 1
@.str.52 = private unnamed_addr constant [7 x i8] c"malloc\00", align 1
@.str.53 = private unnamed_addr constant [6 x i8] c"%%t%d\00", align 1
@.str.54 = private unnamed_addr constant [4 x i8] c"%ld\00", align 1
@.str.55 = private unnamed_addr constant [69 x i8] c"  %s = getelementptr inbounds [%d x i8], ptr @.str.%d, i64 0, i64 0\0A\00", align 1
@.str.56 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.57 = private unnamed_addr constant [138 x i8] c"@.q%d = private unnamed_addr constant { i32, i32, i64, ptr, ptr, ptr } { i32 0, i32 %d, i64 %ld, ptr null, ptr null, ptr null }, align 8\0A\00", align 1
@.str.58 = private unnamed_addr constant [7 x i8] c"@.q%ld\00", align 1
@.str.59 = private unnamed_addr constant [195 x i8] c"@.q%d = private unnamed_addr constant { i32, i32, i64, ptr, ptr, ptr } { i32 %d, i32 %d, i64 0, ptr getelementptr inbounds ([%d x i8], ptr @.str.%d, i64 0, i64 0), ptr null, ptr null }, align 8\0A\00", align 1
@.str.60 = private unnamed_addr constant [7 x i8] c"@.q%ld\00", align 1
@.str.61 = private unnamed_addr constant [132 x i8] c"@.q%d = private unnamed_addr constant { i32, i32, i64, ptr, ptr, ptr } { i32 3, i32 %d, i64 0, ptr null, ptr %s, ptr %s }, align 8\0A\00", align 1
@.str.62 = private unnamed_addr constant [7 x i8] c"@.q%ld\00", align 1
@.str.63 = private unnamed_addr constant [21 x i8] c"quote: expects 1 arg\00", align 1
@.str.64 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.65 = private unnamed_addr constant [15 x i8] c"unquote-splice\00", align 1
@.str.66 = private unnamed_addr constant [43 x i8] c"  %s = call ptr @__append(ptr %s, ptr %s)\0A\00", align 1
@.str.67 = private unnamed_addr constant [41 x i8] c"  %s = call ptr @__cons(ptr %s, ptr %s)\0A\00", align 1
@.str.68 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.69 = private unnamed_addr constant [8 x i8] c"unquote\00", align 1
@.str.70 = private unnamed_addr constant [15 x i8] c"unquote-splice\00", align 1
@.str.71 = private unnamed_addr constant [28 x i8] c"unquote-splice outside list\00", align 1
@.str.72 = private unnamed_addr constant [26 x i8] c"quasiquote: expects 1 arg\00", align 1
@.str.73 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.74 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.75 = private unnamed_addr constant [5 x i8] c"true\00", align 1
@.str.76 = private unnamed_addr constant [2 x i8] c"1\00", align 1
@.str.77 = private unnamed_addr constant [6 x i8] c"false\00", align 1
@.str.78 = private unnamed_addr constant [2 x i8] c"0\00", align 1
@.str.79 = private unnamed_addr constant [14 x i8] c"undefined: %s\00", align 1
@.str.80 = private unnamed_addr constant [34 x i8] c"cannot use function '%s' as value\00", align 1
@.str.81 = private unnamed_addr constant [34 x i8] c"  %s = load %s, ptr %s, align %d\0A\00", align 1
@.str.82 = private unnamed_addr constant [2 x i8] c"+\00", align 1
@.str.83 = private unnamed_addr constant [8 x i8] c"add nsw\00", align 1
@.str.84 = private unnamed_addr constant [2 x i8] c"-\00", align 1
@.str.85 = private unnamed_addr constant [8 x i8] c"sub nsw\00", align 1
@.str.86 = private unnamed_addr constant [2 x i8] c"*\00", align 1
@.str.87 = private unnamed_addr constant [8 x i8] c"mul nsw\00", align 1
@.str.88 = private unnamed_addr constant [2 x i8] c"/\00", align 1
@.str.89 = private unnamed_addr constant [5 x i8] c"sdiv\00", align 1
@.str.90 = private unnamed_addr constant [2 x i8] c"%\00", align 1
@.str.91 = private unnamed_addr constant [5 x i8] c"srem\00", align 1
@.str.92 = private unnamed_addr constant [8 x i8] c"bit-and\00", align 1
@.str.93 = private unnamed_addr constant [4 x i8] c"and\00", align 1
@.str.94 = private unnamed_addr constant [7 x i8] c"bit-or\00", align 1
@.str.95 = private unnamed_addr constant [3 x i8] c"or\00", align 1
@.str.96 = private unnamed_addr constant [8 x i8] c"bit-xor\00", align 1
@.str.97 = private unnamed_addr constant [4 x i8] c"xor\00", align 1
@.str.98 = private unnamed_addr constant [8 x i8] c"bit-shl\00", align 1
@.str.99 = private unnamed_addr constant [4 x i8] c"shl\00", align 1
@.str.100 = private unnamed_addr constant [8 x i8] c"bit-shr\00", align 1
@.str.101 = private unnamed_addr constant [5 x i8] c"ashr\00", align 1
@.str.102 = private unnamed_addr constant [2 x i8] c"=\00", align 1
@.str.103 = private unnamed_addr constant [8 x i8] c"icmp eq\00", align 1
@.str.104 = private unnamed_addr constant [3 x i8] c"!=\00", align 1
@.str.105 = private unnamed_addr constant [8 x i8] c"icmp ne\00", align 1
@.str.106 = private unnamed_addr constant [2 x i8] c"<\00", align 1
@.str.107 = private unnamed_addr constant [9 x i8] c"icmp slt\00", align 1
@.str.108 = private unnamed_addr constant [3 x i8] c"<=\00", align 1
@.str.109 = private unnamed_addr constant [9 x i8] c"icmp sle\00", align 1
@.str.110 = private unnamed_addr constant [2 x i8] c">\00", align 1
@.str.111 = private unnamed_addr constant [9 x i8] c"icmp sgt\00", align 1
@.str.112 = private unnamed_addr constant [3 x i8] c">=\00", align 1
@.str.113 = private unnamed_addr constant [9 x i8] c"icmp sge\00", align 1
@.str.114 = private unnamed_addr constant [18 x i8] c"%s expects 2 args\00", align 1
@.str.115 = private unnamed_addr constant [22 x i8] c"  %s = %s ptr %s, %s\0A\00", align 1
@.str.116 = private unnamed_addr constant [28 x i8] c"%s expects integer operands\00", align 1
@.str.117 = private unnamed_addr constant [25 x i8] c"%s operand type mismatch\00", align 1
@.str.118 = private unnamed_addr constant [21 x i8] c"  %s = %s %s %s, %s\0A\00", align 1
@.str.119 = private unnamed_addr constant [20 x i8] c"cast expects 2 args\00", align 1
@.str.120 = private unnamed_addr constant [35 x i8] c"cast: target type must be a symbol\00", align 1
@.str.121 = private unnamed_addr constant [6 x i8] c"trunc\00", align 1
@.str.122 = private unnamed_addr constant [5 x i8] c"sext\00", align 1
@.str.123 = private unnamed_addr constant [9 x i8] c"inttoptr\00", align 1
@.str.124 = private unnamed_addr constant [9 x i8] c"ptrtoint\00", align 1
@.str.125 = private unnamed_addr constant [29 x i8] c"cast: unsupported conversion\00", align 1
@.str.126 = private unnamed_addr constant [23 x i8] c"  %s = %s %s %s to %s\0A\00", align 1
@.str.127 = private unnamed_addr constant [17 x i8] c". expects 2 args\00", align 1
@.str.128 = private unnamed_addr constant [37 x i8] c".: operand must be pointer to struct\00", align 1
@.str.129 = private unnamed_addr constant [29 x i8] c".: field name must be symbol\00", align 1
@.str.130 = private unnamed_addr constant [32 x i8] c".: no field '%s' on struct '%s'\00", align 1
@.str.131 = private unnamed_addr constant [59 x i8] c"  %s = getelementptr inbounds %%%s, ptr %s, i32 0, i32 %d\0A\00", align 1
@.str.132 = private unnamed_addr constant [34 x i8] c"  %s = load %s, ptr %s, align %d\0A\00", align 1
@.str.133 = private unnamed_addr constant [21 x i8] c".set! expects 3 args\00", align 1
@.str.134 = private unnamed_addr constant [41 x i8] c".set!: operand must be pointer to struct\00", align 1
@.str.135 = private unnamed_addr constant [33 x i8] c".set!: field name must be symbol\00", align 1
@.str.136 = private unnamed_addr constant [36 x i8] c".set!: no field '%s' on struct '%s'\00", align 1
@.str.137 = private unnamed_addr constant [36 x i8] c".set!: type mismatch for field '%s'\00", align 1
@.str.138 = private unnamed_addr constant [59 x i8] c"  %s = getelementptr inbounds %%%s, ptr %s, i32 0, i32 %d\0A\00", align 1
@.str.139 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.140 = private unnamed_addr constant [21 x i8] c"sizeof expects 1 arg\00", align 1
@.str.141 = private unnamed_addr constant [30 x i8] c"sizeof: arg must be type name\00", align 1
@.str.142 = private unnamed_addr constant [42 x i8] c"  %s = getelementptr %s, ptr null, i32 1\0A\00", align 1
@.str.143 = private unnamed_addr constant [31 x i8] c"  %s = ptrtoint ptr %s to i64\0A\00", align 1
@.str.144 = private unnamed_addr constant [27 x i8] c"alloca expects 1 or 2 args\00", align 1
@.str.145 = private unnamed_addr constant [36 x i8] c"alloca: first arg must be type name\00", align 1
@.str.146 = private unnamed_addr constant [36 x i8] c"  %s = alloca %s, i32 %s, align %d\0A\00", align 1
@.str.147 = private unnamed_addr constant [28 x i8] c"  %s = alloca %s, align %d\0A\00", align 1
@.str.148 = private unnamed_addr constant [20 x i8] c"aref expects 2 args\00", align 1
@.str.149 = private unnamed_addr constant [36 x i8] c"aref: operand must be typed pointer\00", align 1
@.str.150 = private unnamed_addr constant [28 x i8] c"aref: index must be integer\00", align 1
@.str.151 = private unnamed_addr constant [26 x i8] c"  %s = sext %s %s to i64\0A\00", align 1
@.str.152 = private unnamed_addr constant [50 x i8] c"  %s = getelementptr inbounds %s, ptr %s, i64 %s\0A\00", align 1
@.str.153 = private unnamed_addr constant [34 x i8] c"  %s = load %s, ptr %s, align %d\0A\00", align 1
@.str.154 = private unnamed_addr constant [21 x i8] c"aset! expects 3 args\00", align 1
@.str.155 = private unnamed_addr constant [37 x i8] c"aset!: operand must be typed pointer\00", align 1
@.str.156 = private unnamed_addr constant [29 x i8] c"aset!: index must be integer\00", align 1
@.str.157 = private unnamed_addr constant [26 x i8] c"  %s = sext %s %s to i64\0A\00", align 1
@.str.158 = private unnamed_addr constant [27 x i8] c"aset!: value type mismatch\00", align 1
@.str.159 = private unnamed_addr constant [50 x i8] c"  %s = getelementptr inbounds %s, ptr %s, i64 %s\0A\00", align 1
@.str.160 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.161 = private unnamed_addr constant [19 x i8] c"char expects 1 arg\00", align 1
@.str.162 = private unnamed_addr constant [37 x i8] c"char: arg must be single-char string\00", align 1
@.str.163 = private unnamed_addr constant [3 x i8] c"%d\00", align 1
@.str.164 = private unnamed_addr constant [22 x i8] c"addr-of expects 1 arg\00", align 1
@.str.165 = private unnamed_addr constant [31 x i8] c"addr-of: target must be symbol\00", align 1
@.str.166 = private unnamed_addr constant [24 x i8] c"addr-of: undefined '%s'\00", align 1
@.str.167 = private unnamed_addr constant [46 x i8] c"addr-of: cannot take address of function '%s'\00", align 1
@.str.168 = private unnamed_addr constant [27 x i8] c"funcall-void expects 1 arg\00", align 1
@.str.169 = private unnamed_addr constant [30 x i8] c"funcall-void: arg must be ptr\00", align 1
@.str.170 = private unnamed_addr constant [18 x i8] c"  call void %s()\0A\00", align 1
@.str.171 = private unnamed_addr constant [29 x i8] c"funcall-ptr-1 expects 2 args\00", align 1
@.str.172 = private unnamed_addr constant [30 x i8] c"funcall-ptr-1: fn must be ptr\00", align 1
@.str.173 = private unnamed_addr constant [31 x i8] c"funcall-ptr-1: arg must be ptr\00", align 1
@.str.174 = private unnamed_addr constant [28 x i8] c"  %s = call ptr %s(ptr %s)\0A\00", align 1
@.str.175 = private unnamed_addr constant [20 x i8] c"deref expects 1 arg\00", align 1
@.str.176 = private unnamed_addr constant [37 x i8] c"deref: operand must be typed pointer\00", align 1
@.str.177 = private unnamed_addr constant [34 x i8] c"  %s = load %s, ptr %s, align %d\0A\00", align 1
@.str.178 = private unnamed_addr constant [24 x i8] c"ptr-set! expects 2 args\00", align 1
@.str.179 = private unnamed_addr constant [40 x i8] c"ptr-set!: operand must be typed pointer\00", align 1
@.str.180 = private unnamed_addr constant [30 x i8] c"ptr-set!: value type mismatch\00", align 1
@.str.181 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.182 = private unnamed_addr constant [20 x i8] c"ptr+ expects 2 args\00", align 1
@.str.183 = private unnamed_addr constant [36 x i8] c"ptr+: operand must be typed pointer\00", align 1
@.str.184 = private unnamed_addr constant [29 x i8] c"ptr+: offset must be integer\00", align 1
@.str.185 = private unnamed_addr constant [26 x i8] c"  %s = sext %s %s to i64\0A\00", align 1
@.str.186 = private unnamed_addr constant [50 x i8] c"  %s = getelementptr inbounds %s, ptr %s, i64 %s\0A\00", align 1
@.str.187 = private unnamed_addr constant [18 x i8] c"not expects 1 arg\00", align 1
@.str.188 = private unnamed_addr constant [23 x i8] c"not expects i1 operand\00", align 1
@.str.189 = private unnamed_addr constant [21 x i8] c"  %s = xor i1 %s, 1\0A\00", align 1
@.str.190 = private unnamed_addr constant [3 x i8] c"or\00", align 1
@.str.191 = private unnamed_addr constant [4 x i8] c"and\00", align 1
@.str.192 = private unnamed_addr constant [18 x i8] c"%s expects 2 args\00", align 1
@.str.193 = private unnamed_addr constant [9 x i8] c"%s.rhs%d\00", align 1
@.str.194 = private unnamed_addr constant [9 x i8] c"%s.end%d\00", align 1
@.str.195 = private unnamed_addr constant [11 x i8] c"%%%s.val%d\00", align 1
@.str.196 = private unnamed_addr constant [27 x i8] c"  %s = alloca i1, align 1\0A\00", align 1
@.str.197 = private unnamed_addr constant [23 x i8] c"%s expects i1 operands\00", align 1
@.str.198 = private unnamed_addr constant [32 x i8] c"  store i1 %s, ptr %s, align 1\0A\00", align 1
@.str.199 = private unnamed_addr constant [36 x i8] c"  br i1 %s, label %%%s, label %%%s\0A\00", align 1
@.str.200 = private unnamed_addr constant [36 x i8] c"  br i1 %s, label %%%s, label %%%s\0A\00", align 1
@.str.201 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.202 = private unnamed_addr constant [23 x i8] c"%s expects i1 operands\00", align 1
@.str.203 = private unnamed_addr constant [32 x i8] c"  store i1 %s, ptr %s, align 1\0A\00", align 1
@.str.204 = private unnamed_addr constant [17 x i8] c"  br label %%%s\0A\00", align 1
@.str.205 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.206 = private unnamed_addr constant [33 x i8] c"  %s = load i1, ptr %s, align 1\0A\00", align 1
@.str.207 = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.208 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.209 = private unnamed_addr constant [8 x i8] c"%s%s %s\00", align 1
@.str.210 = private unnamed_addr constant [19 x i8] c"not a function: %s\00", align 1
@.str.211 = private unnamed_addr constant [5 x i8] c"%s (\00", align 1
@.str.212 = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.213 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.214 = private unnamed_addr constant [5 x i8] c"%s%s\00", align 1
@.str.215 = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.216 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.217 = private unnamed_addr constant [7 x i8] c"%s...)\00", align 1
@.str.218 = private unnamed_addr constant [18 x i8] c"  call %s %s(%s)\0A\00", align 1
@.str.219 = private unnamed_addr constant [23 x i8] c"  %s = call %s %s(%s)\0A\00", align 1
@.str.220 = private unnamed_addr constant [18 x i8] c"  call %s %s(%s)\0A\00", align 1
@.str.221 = private unnamed_addr constant [23 x i8] c"  %s = call %s %s(%s)\0A\00", align 1
@.str.222 = private unnamed_addr constant [12 x i8] c"  ret void\0A\00", align 1
@.str.223 = private unnamed_addr constant [27 x i8] c"return expects 0 or 1 args\00", align 1
@.str.224 = private unnamed_addr constant [13 x i8] c"  ret %s %s\0A\00", align 1
@.str.225 = private unnamed_addr constant [14 x i8] c"let: bad form\00", align 1
@.str.226 = private unnamed_addr constant [31 x i8] c"let: binding list must be even\00", align 1
@.str.227 = private unnamed_addr constant [33 x i8] c"let: binding name must be symbol\00", align 1
@.str.228 = private unnamed_addr constant [27 x i8] c"let: missing :type on '%s'\00", align 1
@.str.229 = private unnamed_addr constant [13 x i8] c"%%%s.addr.%d\00", align 1
@.str.230 = private unnamed_addr constant [28 x i8] c"  %s = alloca %s, align %d\0A\00", align 1
@.str.231 = private unnamed_addr constant [33 x i8] c"let: init type mismatch for '%s'\00", align 1
@.str.232 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.233 = private unnamed_addr constant [35 x i8] c"cond: expects pairs of (test body)\00", align 1
@.str.234 = private unnamed_addr constant [11 x i8] c"cond.end%d\00", align 1
@.str.235 = private unnamed_addr constant [15 x i8] c"cond.then%d.%d\00", align 1
@.str.236 = private unnamed_addr constant [15 x i8] c"cond.test%d.%d\00", align 1
@.str.237 = private unnamed_addr constant [22 x i8] c"cond: test must be i1\00", align 1
@.str.238 = private unnamed_addr constant [36 x i8] c"  br i1 %s, label %%%s, label %%%s\0A\00", align 1
@.str.239 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.240 = private unnamed_addr constant [17 x i8] c"  br label %%%s\0A\00", align 1
@.str.241 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.242 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.243 = private unnamed_addr constant [25 x i8] c"while: missing condition\00", align 1
@.str.244 = private unnamed_addr constant [13 x i8] c"while.cond%d\00", align 1
@.str.245 = private unnamed_addr constant [13 x i8] c"while.body%d\00", align 1
@.str.246 = private unnamed_addr constant [12 x i8] c"while.end%d\00", align 1
@.str.247 = private unnamed_addr constant [17 x i8] c"  br label %%%s\0A\00", align 1
@.str.248 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.249 = private unnamed_addr constant [27 x i8] c"while condition must be i1\00", align 1
@.str.250 = private unnamed_addr constant [36 x i8] c"  br i1 %s, label %%%s, label %%%s\0A\00", align 1
@.str.251 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.252 = private unnamed_addr constant [17 x i8] c"  br label %%%s\0A\00", align 1
@.str.253 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.254 = private unnamed_addr constant [20 x i8] c"set! expects 2 args\00", align 1
@.str.255 = private unnamed_addr constant [28 x i8] c"set!: target must be symbol\00", align 1
@.str.256 = private unnamed_addr constant [27 x i8] c"set!: undefined local '%s'\00", align 1
@.str.257 = private unnamed_addr constant [29 x i8] c"set!: type mismatch for '%s'\00", align 1
@.str.258 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.259 = private unnamed_addr constant [19 x i8] c"inc! expects 1 arg\00", align 1
@.str.260 = private unnamed_addr constant [28 x i8] c"inc!: target must be symbol\00", align 1
@.str.261 = private unnamed_addr constant [27 x i8] c"inc!: undefined local '%s'\00", align 1
@.str.262 = private unnamed_addr constant [22 x i8] c"inc!: must be integer\00", align 1
@.str.263 = private unnamed_addr constant [34 x i8] c"  %s = load %s, ptr %s, align %d\0A\00", align 1
@.str.264 = private unnamed_addr constant [25 x i8] c"  %s = add nsw %s %s, 1\0A\00", align 1
@.str.265 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.266 = private unnamed_addr constant [23 x i8] c"macro: not enough args\00", align 1
@.str.267 = private unnamed_addr constant [28 x i8] c"macro: wrong number of args\00", align 1
@.str.268 = private unnamed_addr constant [35 x i8] c"%s: macro '%s': JIT lookup failed\0A\00", align 1
@.str.269 = private unnamed_addr constant [40 x i8] c"%s: macro '%s': JIT function not found\0A\00", align 1
@.str.270 = private unnamed_addr constant [31 x i8] c"%s: macro '%s': returned null\0A\00", align 1
@.str.271 = private unnamed_addr constant [11 x i8] c"empty list\00", align 1
@.str.272 = private unnamed_addr constant [25 x i8] c"list head must be symbol\00", align 1
@.str.273 = private unnamed_addr constant [7 x i8] c"gensym\00", align 1
@.str.274 = private unnamed_addr constant [35 x i8] c"  %s = call ptr @nucleus_gensym()\0A\00", align 1
@.str.275 = private unnamed_addr constant [14 x i8] c"funcall-ptr-1\00", align 1
@.str.276 = private unnamed_addr constant [7 x i8] c"return\00", align 1
@.str.277 = private unnamed_addr constant [3 x i8] c"do\00", align 1
@.str.278 = private unnamed_addr constant [4 x i8] c"let\00", align 1
@.str.279 = private unnamed_addr constant [5 x i8] c"cond\00", align 1
@.str.280 = private unnamed_addr constant [6 x i8] c"quote\00", align 1
@.str.281 = private unnamed_addr constant [11 x i8] c"quasiquote\00", align 1
@.str.282 = private unnamed_addr constant [6 x i8] c"while\00", align 1
@.str.283 = private unnamed_addr constant [5 x i8] c"set!\00", align 1
@.str.284 = private unnamed_addr constant [5 x i8] c"inc!\00", align 1
@.str.285 = private unnamed_addr constant [4 x i8] c"not\00", align 1
@.str.286 = private unnamed_addr constant [4 x i8] c"and\00", align 1
@.str.287 = private unnamed_addr constant [3 x i8] c"or\00", align 1
@.str.288 = private unnamed_addr constant [5 x i8] c"cast\00", align 1
@.str.289 = private unnamed_addr constant [8 x i8] c"addr-of\00", align 1
@.str.290 = private unnamed_addr constant [13 x i8] c"funcall-void\00", align 1
@.str.291 = private unnamed_addr constant [6 x i8] c"deref\00", align 1
@.str.292 = private unnamed_addr constant [9 x i8] c"ptr-set!\00", align 1
@.str.293 = private unnamed_addr constant [5 x i8] c"ptr+\00", align 1
@.str.294 = private unnamed_addr constant [2 x i8] c".\00", align 1
@.str.295 = private unnamed_addr constant [6 x i8] c".set!\00", align 1
@.str.296 = private unnamed_addr constant [7 x i8] c"sizeof\00", align 1
@.str.297 = private unnamed_addr constant [7 x i8] c"alloca\00", align 1
@.str.298 = private unnamed_addr constant [5 x i8] c"char\00", align 1
@.str.299 = private unnamed_addr constant [5 x i8] c"aref\00", align 1
@.str.300 = private unnamed_addr constant [6 x i8] c"aset!\00", align 1
@.str.301 = private unnamed_addr constant [12 x i8] c"unknown: %s\00", align 1
@.str.302 = private unnamed_addr constant [39 x i8] c"defvar: expects name and optional init\00", align 1
@.str.303 = private unnamed_addr constant [28 x i8] c"defvar: name must be symbol\00", align 1
@.str.304 = private unnamed_addr constant [30 x i8] c"defvar: missing :type on '%s'\00", align 1
@.str.305 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.306 = private unnamed_addr constant [37 x i8] c"defvar: init must be integer literal\00", align 1
@.str.307 = private unnamed_addr constant [31 x i8] c"%s = global %s %ld, align %d\0A\0A\00", align 1
@.str.308 = private unnamed_addr constant [2 x i8] c"0\00", align 1
@.str.309 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.310 = private unnamed_addr constant [30 x i8] c"%s = global %s %s, align %d\0A\0A\00", align 1
@.str.311 = private unnamed_addr constant [33 x i8] c"defconst: expects name and value\00", align 1
@.str.312 = private unnamed_addr constant [30 x i8] c"defconst: name must be symbol\00", align 1
@.str.313 = private unnamed_addr constant [40 x i8] c"defconst: value must be integer literal\00", align 1
@.str.314 = private unnamed_addr constant [4 x i8] c"%ld\00", align 1
@.str.315 = private unnamed_addr constant [22 x i8] c"defenum: missing name\00", align 1
@.str.316 = private unnamed_addr constant [30 x i8] c"defenum: value must be symbol\00", align 1
@.str.317 = private unnamed_addr constant [3 x i8] c"%d\00", align 1
@.str.318 = private unnamed_addr constant [24 x i8] c"defstruct: missing name\00", align 1
@.str.319 = private unnamed_addr constant [31 x i8] c"defstruct: name must be symbol\00", align 1
@.str.320 = private unnamed_addr constant [38 x i8] c"defstruct: field must be typed symbol\00", align 1
@.str.321 = private unnamed_addr constant [36 x i8] c"defstruct: field '%s' missing :type\00", align 1
@.str.322 = private unnamed_addr constant [15 x i8] c"%%%s = type { \00", align 1
@.str.323 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.324 = private unnamed_addr constant [3 x i8] c"%s\00", align 1
@.str.325 = private unnamed_addr constant [5 x i8] c" }\0A\0A\00", align 1
@.str.326 = private unnamed_addr constant [26 x i8] c"extern: expects name:type\00", align 1
@.str.327 = private unnamed_addr constant [30 x i8] c"extern: missing :type on '%s'\00", align 1
@.str.328 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.329 = private unnamed_addr constant [26 x i8] c"%s = external global %s\0A\0A\00", align 1
@.str.330 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.331 = private unnamed_addr constant [7 x i8] c"printf\00", align 1
@.str.332 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.333 = private unnamed_addr constant [8 x i8] c"fprintf\00", align 1
@.str.334 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.335 = private unnamed_addr constant [9 x i8] c"snprintf\00", align 1
@.str.336 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.337 = private unnamed_addr constant [6 x i8] c"fputc\00", align 1
@.str.338 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.339 = private unnamed_addr constant [6 x i8] c"fputs\00", align 1
@.str.340 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.341 = private unnamed_addr constant [6 x i8] c"fopen\00", align 1
@.str.342 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.343 = private unnamed_addr constant [7 x i8] c"fclose\00", align 1
@.str.344 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.345 = private unnamed_addr constant [6 x i8] c"fread\00", align 1
@.str.346 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.347 = private unnamed_addr constant [7 x i8] c"fwrite\00", align 1
@.str.348 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.349 = private unnamed_addr constant [6 x i8] c"fseek\00", align 1
@.str.350 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.351 = private unnamed_addr constant [6 x i8] c"ftell\00", align 1
@.str.352 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.353 = private unnamed_addr constant [7 x i8] c"rewind\00", align 1
@.str.354 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.355 = private unnamed_addr constant [7 x i8] c"perror\00", align 1
@.str.356 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.357 = private unnamed_addr constant [15 x i8] c"open_memstream\00", align 1
@.str.358 = private unnamed_addr constant [6 x i8] c"stdio\00", align 1
@.str.359 = private unnamed_addr constant [7 x i8] c"fflush\00", align 1
@.str.360 = private unnamed_addr constant [7 x i8] c"stdlib\00", align 1
@.str.361 = private unnamed_addr constant [7 x i8] c"malloc\00", align 1
@.str.362 = private unnamed_addr constant [7 x i8] c"stdlib\00", align 1
@.str.363 = private unnamed_addr constant [8 x i8] c"realloc\00", align 1
@.str.364 = private unnamed_addr constant [7 x i8] c"stdlib\00", align 1
@.str.365 = private unnamed_addr constant [5 x i8] c"free\00", align 1
@.str.366 = private unnamed_addr constant [7 x i8] c"stdlib\00", align 1
@.str.367 = private unnamed_addr constant [5 x i8] c"exit\00", align 1
@.str.368 = private unnamed_addr constant [7 x i8] c"stdlib\00", align 1
@.str.369 = private unnamed_addr constant [7 x i8] c"strtol\00", align 1
@.str.370 = private unnamed_addr constant [7 x i8] c"string\00", align 1
@.str.371 = private unnamed_addr constant [7 x i8] c"memcpy\00", align 1
@.str.372 = private unnamed_addr constant [7 x i8] c"string\00", align 1
@.str.373 = private unnamed_addr constant [7 x i8] c"memset\00", align 1
@.str.374 = private unnamed_addr constant [7 x i8] c"string\00", align 1
@.str.375 = private unnamed_addr constant [7 x i8] c"memcmp\00", align 1
@.str.376 = private unnamed_addr constant [7 x i8] c"string\00", align 1
@.str.377 = private unnamed_addr constant [7 x i8] c"strlen\00", align 1
@.str.378 = private unnamed_addr constant [7 x i8] c"string\00", align 1
@.str.379 = private unnamed_addr constant [7 x i8] c"strcmp\00", align 1
@.str.380 = private unnamed_addr constant [7 x i8] c"string\00", align 1
@.str.381 = private unnamed_addr constant [8 x i8] c"strncmp\00", align 1
@.str.382 = private unnamed_addr constant [7 x i8] c"string\00", align 1
@.str.383 = private unnamed_addr constant [7 x i8] c"strchr\00", align 1
@.str.384 = private unnamed_addr constant [7 x i8] c"string\00", align 1
@.str.385 = private unnamed_addr constant [8 x i8] c"strndup\00", align 1
@.str.386 = private unnamed_addr constant [6 x i8] c"ctype\00", align 1
@.str.387 = private unnamed_addr constant [8 x i8] c"isspace\00", align 1
@.str.388 = private unnamed_addr constant [6 x i8] c"ctype\00", align 1
@.str.389 = private unnamed_addr constant [8 x i8] c"isdigit\00", align 1
@.str.390 = private unnamed_addr constant [7 x i8] c"unistd\00", align 1
@.str.391 = private unnamed_addr constant [4 x i8] c"dup\00", align 1
@.str.392 = private unnamed_addr constant [7 x i8] c"unistd\00", align 1
@.str.393 = private unnamed_addr constant [5 x i8] c"dup2\00", align 1
@.str.394 = private unnamed_addr constant [7 x i8] c"unistd\00", align 1
@.str.395 = private unnamed_addr constant [6 x i8] c"close\00", align 1
@.str.396 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.397 = private unnamed_addr constant [28 x i8] c"LLVMInitializeX86TargetInfo\00", align 1
@.str.398 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.399 = private unnamed_addr constant [24 x i8] c"LLVMInitializeX86Target\00", align 1
@.str.400 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.401 = private unnamed_addr constant [26 x i8] c"LLVMInitializeX86TargetMC\00", align 1
@.str.402 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.403 = private unnamed_addr constant [28 x i8] c"LLVMInitializeX86AsmPrinter\00", align 1
@.str.404 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.405 = private unnamed_addr constant [19 x i8] c"LLVMOrcCreateLLJIT\00", align 1
@.str.406 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.407 = private unnamed_addr constant [28 x i8] c"LLVMOrcLLJITGetMainJITDylib\00", align 1
@.str.408 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.409 = private unnamed_addr constant [28 x i8] c"LLVMOrcLLJITGetGlobalPrefix\00", align 1
@.str.410 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.411 = private unnamed_addr constant [53 x i8] c"LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess\00", align 1
@.str.412 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.413 = private unnamed_addr constant [28 x i8] c"LLVMOrcJITDylibAddGenerator\00", align 1
@.str.414 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.415 = private unnamed_addr constant [18 x i8] c"LLVMContextCreate\00", align 1
@.str.416 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.417 = private unnamed_addr constant [34 x i8] c"LLVMOrcCreateNewThreadSafeContext\00", align 1
@.str.418 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.419 = private unnamed_addr constant [32 x i8] c"LLVMOrcDisposeThreadSafeContext\00", align 1
@.str.420 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.421 = private unnamed_addr constant [33 x i8] c"LLVMOrcCreateNewThreadSafeModule\00", align 1
@.str.422 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.423 = private unnamed_addr constant [42 x i8] c"LLVMCreateMemoryBufferWithMemoryRangeCopy\00", align 1
@.str.424 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.425 = private unnamed_addr constant [21 x i8] c"LLVMParseIRInContext\00", align 1
@.str.426 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.427 = private unnamed_addr constant [28 x i8] c"LLVMOrcLLJITAddLLVMIRModule\00", align 1
@.str.428 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.429 = private unnamed_addr constant [19 x i8] c"LLVMOrcLLJITLookup\00", align 1
@.str.430 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.431 = private unnamed_addr constant [20 x i8] c"LLVMGetErrorMessage\00", align 1
@.str.432 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.433 = private unnamed_addr constant [24 x i8] c"LLVMDisposeErrorMessage\00", align 1
@.str.434 = private unnamed_addr constant [5 x i8] c"llvm\00", align 1
@.str.435 = private unnamed_addr constant [17 x i8] c"LLVMConsumeError\00", align 1
@.str.436 = private unnamed_addr constant [28 x i8] c"include: expects one symbol\00", align 1
@.str.437 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.438 = private unnamed_addr constant [7 x i8] c"malloc\00", align 1
@.str.439 = private unnamed_addr constant [16 x i8] c"declare %s @%s(\00", align 1
@.str.440 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.441 = private unnamed_addr constant [3 x i8] c"%s\00", align 1
@.str.442 = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.443 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.444 = private unnamed_addr constant [6 x i8] c"%s...\00", align 1
@.str.445 = private unnamed_addr constant [3 x i8] c")\0A\00", align 1
@.str.446 = private unnamed_addr constant [2 x i8] c"\0A\00", align 1
@.str.447 = private unnamed_addr constant [20 x i8] c"unknown include: %s\00", align 1
@.str.448 = private unnamed_addr constant [15 x i8] c"defn: bad form\00", align 1
@.str.449 = private unnamed_addr constant [26 x i8] c"defn: name must be symbol\00", align 1
@.str.450 = private unnamed_addr constant [26 x i8] c"defn: params must be list\00", align 1
@.str.451 = private unnamed_addr constant [28 x i8] c"defn: missing :type on '%s'\00", align 1
@.str.452 = private unnamed_addr constant [27 x i8] c"defn: param must be symbol\00", align 1
@.str.453 = private unnamed_addr constant [34 x i8] c"defn: missing :type on param '%s'\00", align 1
@.str.454 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.455 = private unnamed_addr constant [10 x i8] c"%%%s.addr\00", align 1
@.str.456 = private unnamed_addr constant [9 x i8] c"%%%s.arg\00", align 1
@.str.457 = private unnamed_addr constant [28 x i8] c"  %s = alloca %s, align %d\0A\00", align 1
@.str.458 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.459 = private unnamed_addr constant [12 x i8] c"  ret void\0A\00", align 1
@.str.460 = private unnamed_addr constant [2 x i8] c"0\00", align 1
@.str.461 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.462 = private unnamed_addr constant [13 x i8] c"  ret %s %s\0A\00", align 1
@.str.463 = private unnamed_addr constant [15 x i8] c"define %s @%s(\00", align 1
@.str.464 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.465 = private unnamed_addr constant [12 x i8] c"%s %%%s.arg\00", align 1
@.str.466 = private unnamed_addr constant [5 x i8] c") {\0A\00", align 1
@.str.467 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.468 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.469 = private unnamed_addr constant [44 x i8] c"%s:%d: JIT error in LLVMOrcCreateLLJIT: %s\0A\00", align 1
@.str.470 = private unnamed_addr constant [47 x i8] c"%s:%d: JIT error in CreateDynLibSearchGen: %s\0A\00", align 1
@.str.471 = private unnamed_addr constant [15 x i8] c"<compile-time>\00", align 1
@.str.472 = private unnamed_addr constant [41 x i8] c"%s:%d: compile-time: IR parse error: %s\0A\00", align 1
@.str.473 = private unnamed_addr constant [41 x i8] c"%s:%d: JIT error in AddLLVMIRModule: %s\0A\00", align 1
@.str.474 = private unnamed_addr constant [46 x i8] c"compile-time: expected at least one body form\00", align 1
@.str.475 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.476 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.477 = private unnamed_addr constant [10 x i8] c"defstruct\00", align 1
@.str.478 = private unnamed_addr constant [9 x i8] c"defconst\00", align 1
@.str.479 = private unnamed_addr constant [8 x i8] c"defenum\00", align 1
@.str.480 = private unnamed_addr constant [7 x i8] c"defvar\00", align 1
@.str.481 = private unnamed_addr constant [8 x i8] c"include\00", align 1
@.str.482 = private unnamed_addr constant [7 x i8] c"extern\00", align 1
@.str.483 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.484 = private unnamed_addr constant [24 x i8] c"__compile_time_main_%ld\00", align 1
@.str.485 = private unnamed_addr constant [12 x i8] c"  ret void\0A\00", align 1
@.str.486 = private unnamed_addr constant [21 x i8] c"define void @%s() {\0A\00", align 1
@.str.487 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.488 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.489 = private unnamed_addr constant [26 x i8] c"declare ptr @malloc(i64)\0A\00", align 1
@.str.490 = private unnamed_addr constant [48 x i8] c"define private ptr @__cons(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.491 = private unnamed_addr constant [34 x i8] c"  %%c = call ptr @malloc(i64 40)\0A\00", align 1
@.str.492 = private unnamed_addr constant [89 x i8] c"  %%p0 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 0\0A\00", align 1
@.str.493 = private unnamed_addr constant [34 x i8] c"  store i32 3, ptr %%p0, align 8\0A\00", align 1
@.str.494 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 4\0A\00", align 1
@.str.495 = private unnamed_addr constant [36 x i8] c"  store ptr %%a, ptr %%p4, align 8\0A\00", align 1
@.str.496 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 5\0A\00", align 1
@.str.497 = private unnamed_addr constant [36 x i8] c"  store ptr %%b, ptr %%p5, align 8\0A\00", align 1
@.str.498 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.499 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.500 = private unnamed_addr constant [50 x i8] c"define private ptr @__append(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.501 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.502 = private unnamed_addr constant [31 x i8] c"  %%z = icmp eq ptr %%a, null\0A\00", align 1
@.str.503 = private unnamed_addr constant [39 x i8] c"  br i1 %%z, label %%nil, label %%rec\0A\00", align 1
@.str.504 = private unnamed_addr constant [6 x i8] c"nil:\0A\00", align 1
@.str.505 = private unnamed_addr constant [15 x i8] c"  ret ptr %%b\0A\00", align 1
@.str.506 = private unnamed_addr constant [6 x i8] c"rec:\0A\00", align 1
@.str.507 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 4\0A\00", align 1
@.str.508 = private unnamed_addr constant [39 x i8] c"  %%car = load ptr, ptr %%p4, align 8\0A\00", align 1
@.str.509 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 5\0A\00", align 1
@.str.510 = private unnamed_addr constant [39 x i8] c"  %%cdr = load ptr, ptr %%p5, align 8\0A\00", align 1
@.str.511 = private unnamed_addr constant [51 x i8] c"  %%rest = call ptr @__append(ptr %%cdr, ptr %%b)\0A\00", align 1
@.str.512 = private unnamed_addr constant [49 x i8] c"  %%c = call ptr @__cons(ptr %%car, ptr %%rest)\0A\00", align 1
@.str.513 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.514 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.515 = private unnamed_addr constant [31 x i8] c"; ModuleID = '<compile-time>'\0A\00", align 1
@.str.516 = private unnamed_addr constant [40 x i8] c"target triple = \22x86_64-pc-linux-gnu\22\0A\0A\00", align 1
@.str.517 = private unnamed_addr constant [41 x i8] c"defmacro: expects name, params, and body\00", align 1
@.str.518 = private unnamed_addr constant [30 x i8] c"defmacro: name must be symbol\00", align 1
@.str.519 = private unnamed_addr constant [32 x i8] c"defmacro: params must be a list\00", align 1
@.str.520 = private unnamed_addr constant [11 x i8] c"__macro_%s\00", align 1
@.str.521 = private unnamed_addr constant [6 x i8] c"&rest\00", align 1
@.str.522 = private unnamed_addr constant [45 x i8] c"defmacro: &rest must be second-to-last param\00", align 1
@.str.523 = private unnamed_addr constant [33 x i8] c"defmacro: param must be a symbol\00", align 1
@.str.524 = private unnamed_addr constant [6 x i8] c"&rest\00", align 1
@.str.525 = private unnamed_addr constant [27 x i8] c"defmacro: macro table full\00", align 1
@.str.526 = private unnamed_addr constant [39 x i8] c"  %%__args.addr = alloca ptr, align 8\0A\00", align 1
@.str.527 = private unnamed_addr constant [54 x i8] c"  store ptr %%__args.arg, ptr %%__args.addr, align 8\0A\00", align 1
@.str.528 = private unnamed_addr constant [35 x i8] c"  %%%s.addr = alloca ptr, align 8\0A\00", align 1
@.str.529 = private unnamed_addr constant [51 x i8] c"  %%__ap%d = load ptr, ptr %%__args.addr, align 8\0A\00", align 1
@.str.530 = private unnamed_addr constant [54 x i8] c"  %%__ag%d = getelementptr ptr, ptr %%__ap%d, i32 %d\0A\00", align 1
@.str.531 = private unnamed_addr constant [46 x i8] c"  %%__av%d = load ptr, ptr %%__ag%d, align 8\0A\00", align 1
@.str.532 = private unnamed_addr constant [46 x i8] c"  store ptr %%__av%d, ptr %%%s.addr, align 8\0A\00", align 1
@.str.533 = private unnamed_addr constant [10 x i8] c"%%%s.addr\00", align 1
@.str.534 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.535 = private unnamed_addr constant [14 x i8] c"  ret ptr %s\0A\00", align 1
@.str.536 = private unnamed_addr constant [36 x i8] c"define ptr @%s(ptr %%__args.arg) {\0A\00", align 1
@.str.537 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.538 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.539 = private unnamed_addr constant [26 x i8] c"declare ptr @malloc(i64)\0A\00", align 1
@.str.540 = private unnamed_addr constant [48 x i8] c"define private ptr @__cons(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.541 = private unnamed_addr constant [34 x i8] c"  %%c = call ptr @malloc(i64 40)\0A\00", align 1
@.str.542 = private unnamed_addr constant [89 x i8] c"  %%p0 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 0\0A\00", align 1
@.str.543 = private unnamed_addr constant [34 x i8] c"  store i32 3, ptr %%p0, align 8\0A\00", align 1
@.str.544 = private unnamed_addr constant [89 x i8] c"  %%p1 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 1\0A\00", align 1
@.str.545 = private unnamed_addr constant [34 x i8] c"  store i32 0, ptr %%p1, align 4\0A\00", align 1
@.str.546 = private unnamed_addr constant [89 x i8] c"  %%p2 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 2\0A\00", align 1
@.str.547 = private unnamed_addr constant [34 x i8] c"  store i64 0, ptr %%p2, align 8\0A\00", align 1
@.str.548 = private unnamed_addr constant [89 x i8] c"  %%p3 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 3\0A\00", align 1
@.str.549 = private unnamed_addr constant [37 x i8] c"  store ptr null, ptr %%p3, align 8\0A\00", align 1
@.str.550 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 4\0A\00", align 1
@.str.551 = private unnamed_addr constant [36 x i8] c"  store ptr %%a, ptr %%p4, align 8\0A\00", align 1
@.str.552 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 5\0A\00", align 1
@.str.553 = private unnamed_addr constant [36 x i8] c"  store ptr %%b, ptr %%p5, align 8\0A\00", align 1
@.str.554 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.555 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.556 = private unnamed_addr constant [50 x i8] c"define private ptr @__append(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.557 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.558 = private unnamed_addr constant [31 x i8] c"  %%z = icmp eq ptr %%a, null\0A\00", align 1
@.str.559 = private unnamed_addr constant [39 x i8] c"  br i1 %%z, label %%nil, label %%rec\0A\00", align 1
@.str.560 = private unnamed_addr constant [6 x i8] c"nil:\0A\00", align 1
@.str.561 = private unnamed_addr constant [15 x i8] c"  ret ptr %%b\0A\00", align 1
@.str.562 = private unnamed_addr constant [6 x i8] c"rec:\0A\00", align 1
@.str.563 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 4\0A\00", align 1
@.str.564 = private unnamed_addr constant [39 x i8] c"  %%car = load ptr, ptr %%p4, align 8\0A\00", align 1
@.str.565 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 5\0A\00", align 1
@.str.566 = private unnamed_addr constant [39 x i8] c"  %%cdr = load ptr, ptr %%p5, align 8\0A\00", align 1
@.str.567 = private unnamed_addr constant [51 x i8] c"  %%rest = call ptr @__append(ptr %%cdr, ptr %%b)\0A\00", align 1
@.str.568 = private unnamed_addr constant [49 x i8] c"  %%c = call ptr @__cons(ptr %%car, ptr %%rest)\0A\00", align 1
@.str.569 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.570 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.571 = private unnamed_addr constant [31 x i8] c"declare ptr @nucleus_gensym()\0A\00", align 1
@.str.572 = private unnamed_addr constant [30 x i8] c"; ModuleID = '<defmacro %s>'\0A\00", align 1
@.str.573 = private unnamed_addr constant [40 x i8] c"target triple = \22x86_64-pc-linux-gnu\22\0A\0A\00", align 1
@.str.574 = private unnamed_addr constant [54 x i8] c"@.str.%d = private unnamed_addr constant [%d x i8] c\22\00", align 1
@.str.575 = private unnamed_addr constant [6 x i8] c"\5C%02X\00", align 1
@.str.576 = private unnamed_addr constant [15 x i8] c"\5C00\22, align 1\0A\00", align 1
@.str.577 = private unnamed_addr constant [3 x i8] c"rb\00", align 1
@.str.578 = private unnamed_addr constant [6 x i8] c"fseek\00", align 1
@.str.579 = private unnamed_addr constant [6 x i8] c"ftell\00", align 1
@.str.580 = private unnamed_addr constant [7 x i8] c"malloc\00", align 1
@.str.581 = private unnamed_addr constant [28 x i8] c"usage: nucleusc <file.nuc>\0A\00", align 1
@.str.582 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.583 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.584 = private unnamed_addr constant [53 x i8] c"top-level form must be a list starting with a symbol\00", align 1
@.str.585 = private unnamed_addr constant [9 x i8] c"defconst\00", align 1
@.str.586 = private unnamed_addr constant [8 x i8] c"defenum\00", align 1
@.str.587 = private unnamed_addr constant [7 x i8] c"defvar\00", align 1
@.str.588 = private unnamed_addr constant [10 x i8] c"defstruct\00", align 1
@.str.589 = private unnamed_addr constant [8 x i8] c"include\00", align 1
@.str.590 = private unnamed_addr constant [7 x i8] c"extern\00", align 1
@.str.591 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.592 = private unnamed_addr constant [13 x i8] c"compile-time\00", align 1
@.str.593 = private unnamed_addr constant [9 x i8] c"defmacro\00", align 1
@.str.594 = private unnamed_addr constant [27 x i8] c"unknown top-level form: %s\00", align 1
@.str.595 = private unnamed_addr constant [26 x i8] c"declare ptr @malloc(i64)\0A\00", align 1
@.str.596 = private unnamed_addr constant [40 x i8] c"define ptr @__cons(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.597 = private unnamed_addr constant [34 x i8] c"  %%c = call ptr @malloc(i64 40)\0A\00", align 1
@.str.598 = private unnamed_addr constant [89 x i8] c"  %%p0 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 0\0A\00", align 1
@.str.599 = private unnamed_addr constant [34 x i8] c"  store i32 3, ptr %%p0, align 8\0A\00", align 1
@.str.600 = private unnamed_addr constant [89 x i8] c"  %%p1 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 1\0A\00", align 1
@.str.601 = private unnamed_addr constant [34 x i8] c"  store i32 0, ptr %%p1, align 4\0A\00", align 1
@.str.602 = private unnamed_addr constant [89 x i8] c"  %%p2 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 2\0A\00", align 1
@.str.603 = private unnamed_addr constant [34 x i8] c"  store i64 0, ptr %%p2, align 8\0A\00", align 1
@.str.604 = private unnamed_addr constant [89 x i8] c"  %%p3 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 3\0A\00", align 1
@.str.605 = private unnamed_addr constant [37 x i8] c"  store ptr null, ptr %%p3, align 8\0A\00", align 1
@.str.606 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 4\0A\00", align 1
@.str.607 = private unnamed_addr constant [36 x i8] c"  store ptr %%a, ptr %%p4, align 8\0A\00", align 1
@.str.608 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 5\0A\00", align 1
@.str.609 = private unnamed_addr constant [36 x i8] c"  store ptr %%b, ptr %%p5, align 8\0A\00", align 1
@.str.610 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.611 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.612 = private unnamed_addr constant [42 x i8] c"define ptr @__append(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.613 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.614 = private unnamed_addr constant [31 x i8] c"  %%z = icmp eq ptr %%a, null\0A\00", align 1
@.str.615 = private unnamed_addr constant [39 x i8] c"  br i1 %%z, label %%nil, label %%rec\0A\00", align 1
@.str.616 = private unnamed_addr constant [6 x i8] c"nil:\0A\00", align 1
@.str.617 = private unnamed_addr constant [15 x i8] c"  ret ptr %%b\0A\00", align 1
@.str.618 = private unnamed_addr constant [6 x i8] c"rec:\0A\00", align 1
@.str.619 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 4\0A\00", align 1
@.str.620 = private unnamed_addr constant [39 x i8] c"  %%car = load ptr, ptr %%p4, align 8\0A\00", align 1
@.str.621 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 5\0A\00", align 1
@.str.622 = private unnamed_addr constant [39 x i8] c"  %%cdr = load ptr, ptr %%p5, align 8\0A\00", align 1
@.str.623 = private unnamed_addr constant [51 x i8] c"  %%rest = call ptr @__append(ptr %%cdr, ptr %%b)\0A\00", align 1
@.str.624 = private unnamed_addr constant [49 x i8] c"  %%c = call ptr @__cons(ptr %%car, ptr %%rest)\0A\00", align 1
@.str.625 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.626 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.627 = private unnamed_addr constant [19 x i8] c"; ModuleID = '%s'\0A\00", align 1
@.str.628 = private unnamed_addr constant [24 x i8] c"source_filename = \22%s\22\0A\00", align 1
@.str.629 = private unnamed_addr constant [40 x i8] c"target triple = \22x86_64-pc-linux-gnu\22\0A\0A\00", align 1

declare i32 @printf(ptr, ...)
declare i32 @fprintf(ptr, ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare i32 @fputc(i32, ptr)
declare i32 @fputs(ptr, ptr)
declare ptr @fopen(ptr, ptr)
declare i32 @fclose(ptr)
declare i64 @fread(ptr, i64, i64, ptr)
declare i64 @fwrite(ptr, i64, i64, ptr)
declare i32 @fseek(ptr, i64, i32)
declare i64 @ftell(ptr)
declare void @rewind(ptr)
declare void @perror(ptr)
declare ptr @open_memstream(ptr, ptr)
declare i32 @fflush(ptr)

declare ptr @memcpy(ptr, ptr, i64)
declare ptr @memset(ptr, i32, i64)
declare i32 @memcmp(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare i32 @strcmp(ptr, ptr)
declare i32 @strncmp(ptr, ptr, i64)
declare ptr @strchr(ptr, i32)
declare ptr @strndup(ptr, i64)

declare i32 @isspace(i32)
declare i32 @isdigit(i32)

declare i32 @dup(i32)
declare i32 @dup2(i32, i32)
declare i32 @close(i32)

declare void @LLVMInitializeX86TargetInfo()
declare void @LLVMInitializeX86Target()
declare void @LLVMInitializeX86TargetMC()
declare void @LLVMInitializeX86AsmPrinter()
declare ptr @LLVMOrcCreateLLJIT(ptr, ptr)
declare ptr @LLVMOrcLLJITGetMainJITDylib(ptr)
declare i8 @LLVMOrcLLJITGetGlobalPrefix(ptr)
declare ptr @LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess(ptr, i8, ptr, ptr)
declare void @LLVMOrcJITDylibAddGenerator(ptr, ptr)
declare ptr @LLVMContextCreate()
declare ptr @LLVMOrcCreateNewThreadSafeContext()
declare void @LLVMOrcDisposeThreadSafeContext(ptr)
declare ptr @LLVMOrcCreateNewThreadSafeModule(ptr, ptr)
declare ptr @LLVMCreateMemoryBufferWithMemoryRangeCopy(ptr, i64, ptr)
declare i32 @LLVMParseIRInContext(ptr, ptr, ptr, ptr)
declare ptr @LLVMOrcLLJITAddLLVMIRModule(ptr, ptr, ptr)
declare ptr @LLVMOrcLLJITLookup(ptr, ptr, ptr)
declare ptr @LLVMGetErrorMessage(ptr)
declare void @LLVMDisposeErrorMessage(ptr)
declare void @LLVMConsumeError(ptr)

@stderr = external global ptr

@stdout = external global ptr

@g-arena = global ptr null, align 8

@g-arena-used = global i64 0, align 8

@g-source-path = global ptr null, align 8

@g-src = global ptr null, align 8

@g-pos = global i64 0, align 8

@g-line = global i32 1, align 4

@g-peek = global ptr null, align 8

@g-peek-valid = global i32 0, align 4

@ty-void = global ptr null, align 8

@ty-i1 = global ptr null, align 8

@ty-i8 = global ptr null, align 8

@ty-i16 = global ptr null, align 8

@ty-i32 = global ptr null, align 8

@ty-i64 = global ptr null, align 8

@ty-ptr = global ptr null, align 8

@g-structs = global ptr null, align 8

@g-structs-len = global i32 0, align 4

@g-globals = global ptr null, align 8

@g-strs = global ptr null, align 8

@g-strs-len = global i32 0, align 4

@g-strs-cap = global i32 0, align 4

@g-tmp = global i32 0, align 4

@g-label = global i32 0, align 4

@g-entry-stream = global ptr null, align 8

@g-entry-bufp = global ptr null, align 8

@g-entry-sizep = global i64 0, align 8

@g-body-stream = global ptr null, align 8

@g-body-bufp = global ptr null, align 8

@g-body-sizep = global i64 0, align 8

@g-block-term = global i32 0, align 4

@g-out = global ptr null, align 8

@g-decl-out = global ptr null, align 8

@g-quote-id = global i32 0, align 4

@g-qq-used = global i32 0, align 4

@g-type-stream = global ptr null, align 8

@g-decl-stream = global ptr null, align 8

@g-def-stream = global ptr null, align 8

@g-type-bufp = global ptr null, align 8

@g-decl-bufp = global ptr null, align 8

@g-def-bufp = global ptr null, align 8

@g-type-sizep = global i64 0, align 8

@g-decl-sizep = global i64 0, align 8

@g-def-sizep = global i64 0, align 8

@g-jit = global ptr null, align 8

@g-jit-dylib = global ptr null, align 8

@g-ct-id = global i32 0, align 4

@g-binops = global ptr null, align 8

@g-num-binops = global i32 0, align 4

@g-libc = global ptr null, align 8

@g-num-libc = global i32 0, align 4

@g-macros = global ptr null, align 8

@g-num-macros = global i32 0, align 4

@g-gensym-id = global i32 0, align 4

@g-malloc-decl-done = global i32 0, align 4

declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare void @exit(i32)
declare i64 @strtol(ptr, ptr, i32)

define void @arena-init() {
entry:
  %t0 = sext i32 16777216 to i64
  %t1 = call ptr @malloc(i64 %t0)
  store ptr %t1, ptr @g-arena, align 8
  %t2 = load ptr, ptr @g-arena, align 8
  %t3 = icmp eq ptr %t2, null
  br i1 %t3, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t4 = getelementptr inbounds [13 x i8], ptr @.str.16, i64 0, i64 0
  call void @perror(ptr %t4)
  call void @exit(i32 1)
  br label %cond.end0
cond.end0:
  %t5 = sext i32 0 to i64
  store i64 %t5, ptr @g-arena-used, align 8
  ret void
}

define ptr @arena-alloc(i64 %n.arg) {
entry:
  %n.addr = alloca i64, align 8
  store i64 %n.arg, ptr %n.addr, align 8
  %p.addr.13 = alloca ptr, align 8
  %t0 = load i64, ptr %n.addr, align 8
  %t1 = sext i32 7 to i64
  %t2 = add nsw i64 %t0, %t1
  %t3 = sext i32 -8 to i64
  %t4 = and i64 %t2, %t3
  store i64 %t4, ptr %n.addr, align 8
  %t5 = load i64, ptr @g-arena-used, align 8
  %t6 = load i64, ptr %n.addr, align 8
  %t7 = add nsw i64 %t5, %t6
  %t8 = sext i32 16777216 to i64
  %t9 = icmp sgt i64 %t7, %t8
  br i1 %t9, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t10 = load ptr, ptr @stderr, align 8
  %t11 = getelementptr inbounds [27 x i8], ptr @.str.17, i64 0, i64 0
  %t12 = call i32 (ptr, ptr, ...) @fprintf(ptr %t10, ptr %t11)
  call void @exit(i32 1)
  br label %cond.end0
cond.end0:
  %t14 = load ptr, ptr @g-arena, align 8
  %t15 = load i64, ptr @g-arena-used, align 8
  %t16 = getelementptr inbounds i8, ptr %t14, i64 %t15
  store ptr %t16, ptr %p.addr.13, align 8
  %t17 = load i64, ptr @g-arena-used, align 8
  %t18 = load i64, ptr %n.addr, align 8
  %t19 = add nsw i64 %t17, %t18
  store i64 %t19, ptr @g-arena-used, align 8
  %t20 = load ptr, ptr %p.addr.13, align 8
  %t21 = load i64, ptr %n.addr, align 8
  %t22 = call ptr @memset(ptr %t20, i32 0, i64 %t21)
  %t23 = load ptr, ptr %p.addr.13, align 8
  ret ptr %t23
}

define ptr @arena-strndup(ptr %s.arg, i64 %n.arg) {
entry:
  %s.addr = alloca ptr, align 8
  store ptr %s.arg, ptr %s.addr, align 8
  %n.addr = alloca i64, align 8
  store i64 %n.arg, ptr %n.addr, align 8
  %p.addr.0 = alloca ptr, align 8
  %t1 = load i64, ptr %n.addr, align 8
  %t2 = sext i32 1 to i64
  %t3 = add nsw i64 %t1, %t2
  %t4 = call ptr @arena-alloc(i64 %t3)
  store ptr %t4, ptr %p.addr.0, align 8
  %t5 = load ptr, ptr %p.addr.0, align 8
  %t6 = load ptr, ptr %s.addr, align 8
  %t7 = load i64, ptr %n.addr, align 8
  %t8 = call ptr @memcpy(ptr %t5, ptr %t6, i64 %t7)
  %t9 = load ptr, ptr %p.addr.0, align 8
  %t10 = load i64, ptr %n.addr, align 8
  %t11 = trunc i32 0 to i8
  %t12 = getelementptr inbounds i8, ptr %t9, i64 %t10
  store i8 %t11, ptr %t12, align 1
  %t13 = load ptr, ptr %p.addr.0, align 8
  ret ptr %t13
}

define ptr @arena-strdup(ptr %s.arg) {
entry:
  %s.addr = alloca ptr, align 8
  store ptr %s.arg, ptr %s.addr, align 8
  %t0 = load ptr, ptr %s.addr, align 8
  %t1 = load ptr, ptr %s.addr, align 8
  %t2 = call i64 @strlen(ptr %t1)
  %t3 = call ptr @arena-strndup(ptr %t0, i64 %t2)
  ret ptr %t3
}

define i64 @i64(i32 %n.arg) {
entry:
  %n.addr = alloca i32, align 4
  store i32 %n.arg, ptr %n.addr, align 4
  %t0 = load i32, ptr %n.addr, align 4
  %t1 = sext i32 %t0 to i64
  ret i64 %t1
}

define ptr @fmt-i32(ptr %fmt.arg, i32 %d.arg) {
entry:
  %fmt.addr = alloca ptr, align 8
  store ptr %fmt.arg, ptr %fmt.addr, align 8
  %d.addr = alloca i32, align 4
  store i32 %d.arg, ptr %d.addr, align 4
  %buf.addr.0 = alloca ptr, align 8
  %n.addr.2 = alloca i32, align 4
  %t1 = alloca i8, i32 256, align 1
  store ptr %t1, ptr %buf.addr.0, align 8
  %t3 = load ptr, ptr %buf.addr.0, align 8
  %t4 = sext i32 256 to i64
  %t5 = load ptr, ptr %fmt.addr, align 8
  %t6 = load i32, ptr %d.addr, align 4
  %t7 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t3, i64 %t4, ptr %t5, i32 %t6)
  store i32 %t7, ptr %n.addr.2, align 4
  %t8 = load ptr, ptr %buf.addr.0, align 8
  %t9 = load i32, ptr %n.addr.2, align 4
  %t10 = call i64 @i64(i32 %t9)
  %t11 = call ptr @arena-strndup(ptr %t8, i64 %t10)
  ret ptr %t11
}

define ptr @fmt-i32-i32(ptr %fmt.arg, i32 %a.arg, i32 %b.arg) {
entry:
  %fmt.addr = alloca ptr, align 8
  store ptr %fmt.arg, ptr %fmt.addr, align 8
  %a.addr = alloca i32, align 4
  store i32 %a.arg, ptr %a.addr, align 4
  %b.addr = alloca i32, align 4
  store i32 %b.arg, ptr %b.addr, align 4
  %buf.addr.0 = alloca ptr, align 8
  %n.addr.2 = alloca i32, align 4
  %t1 = alloca i8, i32 256, align 1
  store ptr %t1, ptr %buf.addr.0, align 8
  %t3 = load ptr, ptr %buf.addr.0, align 8
  %t4 = sext i32 256 to i64
  %t5 = load ptr, ptr %fmt.addr, align 8
  %t6 = load i32, ptr %a.addr, align 4
  %t7 = load i32, ptr %b.addr, align 4
  %t8 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t3, i64 %t4, ptr %t5, i32 %t6, i32 %t7)
  store i32 %t8, ptr %n.addr.2, align 4
  %t9 = load ptr, ptr %buf.addr.0, align 8
  %t10 = load i32, ptr %n.addr.2, align 4
  %t11 = call i64 @i64(i32 %t10)
  %t12 = call ptr @arena-strndup(ptr %t9, i64 %t11)
  ret ptr %t12
}

define ptr @fmt-i64(ptr %fmt.arg, i64 %d.arg) {
entry:
  %fmt.addr = alloca ptr, align 8
  store ptr %fmt.arg, ptr %fmt.addr, align 8
  %d.addr = alloca i64, align 8
  store i64 %d.arg, ptr %d.addr, align 8
  %buf.addr.0 = alloca ptr, align 8
  %n.addr.2 = alloca i32, align 4
  %t1 = alloca i8, i32 256, align 1
  store ptr %t1, ptr %buf.addr.0, align 8
  %t3 = load ptr, ptr %buf.addr.0, align 8
  %t4 = sext i32 256 to i64
  %t5 = load ptr, ptr %fmt.addr, align 8
  %t6 = load i64, ptr %d.addr, align 8
  %t7 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t3, i64 %t4, ptr %t5, i64 %t6)
  store i32 %t7, ptr %n.addr.2, align 4
  %t8 = load ptr, ptr %buf.addr.0, align 8
  %t9 = load i32, ptr %n.addr.2, align 4
  %t10 = call i64 @i64(i32 %t9)
  %t11 = call ptr @arena-strndup(ptr %t8, i64 %t10)
  ret ptr %t11
}

define ptr @fmt-s(ptr %fmt.arg, ptr %s.arg) {
entry:
  %fmt.addr = alloca ptr, align 8
  store ptr %fmt.arg, ptr %fmt.addr, align 8
  %s.addr = alloca ptr, align 8
  store ptr %s.arg, ptr %s.addr, align 8
  %buf.addr.0 = alloca ptr, align 8
  %n.addr.2 = alloca i32, align 4
  %t1 = alloca i8, i32 512, align 1
  store ptr %t1, ptr %buf.addr.0, align 8
  %t3 = load ptr, ptr %buf.addr.0, align 8
  %t4 = sext i32 512 to i64
  %t5 = load ptr, ptr %fmt.addr, align 8
  %t6 = load ptr, ptr %s.addr, align 8
  %t7 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t3, i64 %t4, ptr %t5, ptr %t6)
  store i32 %t7, ptr %n.addr.2, align 4
  %t8 = load ptr, ptr %buf.addr.0, align 8
  %t9 = load i32, ptr %n.addr.2, align 4
  %t10 = call i64 @i64(i32 %t9)
  %t11 = call ptr @arena-strndup(ptr %t8, i64 %t10)
  ret ptr %t11
}

define ptr @fmt-sd(ptr %fmt.arg, ptr %s.arg, i32 %d.arg) {
entry:
  %fmt.addr = alloca ptr, align 8
  store ptr %fmt.arg, ptr %fmt.addr, align 8
  %s.addr = alloca ptr, align 8
  store ptr %s.arg, ptr %s.addr, align 8
  %d.addr = alloca i32, align 4
  store i32 %d.arg, ptr %d.addr, align 4
  %buf.addr.0 = alloca ptr, align 8
  %n.addr.2 = alloca i32, align 4
  %t1 = alloca i8, i32 512, align 1
  store ptr %t1, ptr %buf.addr.0, align 8
  %t3 = load ptr, ptr %buf.addr.0, align 8
  %t4 = sext i32 512 to i64
  %t5 = load ptr, ptr %fmt.addr, align 8
  %t6 = load ptr, ptr %s.addr, align 8
  %t7 = load i32, ptr %d.addr, align 4
  %t8 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t3, i64 %t4, ptr %t5, ptr %t6, i32 %t7)
  store i32 %t8, ptr %n.addr.2, align 4
  %t9 = load ptr, ptr %buf.addr.0, align 8
  %t10 = load i32, ptr %n.addr.2, align 4
  %t11 = call i64 @i64(i32 %t10)
  %t12 = call ptr @arena-strndup(ptr %t9, i64 %t11)
  ret ptr %t12
}

define ptr @fmt-2s(ptr %fmt.arg, ptr %s1.arg, ptr %s2.arg) {
entry:
  %fmt.addr = alloca ptr, align 8
  store ptr %fmt.arg, ptr %fmt.addr, align 8
  %s1.addr = alloca ptr, align 8
  store ptr %s1.arg, ptr %s1.addr, align 8
  %s2.addr = alloca ptr, align 8
  store ptr %s2.arg, ptr %s2.addr, align 8
  %buf.addr.0 = alloca ptr, align 8
  %n.addr.2 = alloca i32, align 4
  %t1 = alloca i8, i32 512, align 1
  store ptr %t1, ptr %buf.addr.0, align 8
  %t3 = load ptr, ptr %buf.addr.0, align 8
  %t4 = sext i32 512 to i64
  %t5 = load ptr, ptr %fmt.addr, align 8
  %t6 = load ptr, ptr %s1.addr, align 8
  %t7 = load ptr, ptr %s2.addr, align 8
  %t8 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t3, i64 %t4, ptr %t5, ptr %t6, ptr %t7)
  store i32 %t8, ptr %n.addr.2, align 4
  %t9 = load ptr, ptr %buf.addr.0, align 8
  %t10 = load i32, ptr %n.addr.2, align 4
  %t11 = call i64 @i64(i32 %t10)
  %t12 = call ptr @arena-strndup(ptr %t9, i64 %t11)
  ret ptr %t12
}

define ptr @fmt-2s-i(ptr %fmt.arg, ptr %s1.arg, ptr %s2.arg, i32 %d.arg) {
entry:
  %fmt.addr = alloca ptr, align 8
  store ptr %fmt.arg, ptr %fmt.addr, align 8
  %s1.addr = alloca ptr, align 8
  store ptr %s1.arg, ptr %s1.addr, align 8
  %s2.addr = alloca ptr, align 8
  store ptr %s2.arg, ptr %s2.addr, align 8
  %d.addr = alloca i32, align 4
  store i32 %d.arg, ptr %d.addr, align 4
  %buf.addr.0 = alloca ptr, align 8
  %n.addr.2 = alloca i32, align 4
  %t1 = alloca i8, i32 512, align 1
  store ptr %t1, ptr %buf.addr.0, align 8
  %t3 = load ptr, ptr %buf.addr.0, align 8
  %t4 = sext i32 512 to i64
  %t5 = load ptr, ptr %fmt.addr, align 8
  %t6 = load ptr, ptr %s1.addr, align 8
  %t7 = load ptr, ptr %s2.addr, align 8
  %t8 = load i32, ptr %d.addr, align 4
  %t9 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t3, i64 %t4, ptr %t5, ptr %t6, ptr %t7, i32 %t8)
  store i32 %t9, ptr %n.addr.2, align 4
  %t10 = load ptr, ptr %buf.addr.0, align 8
  %t11 = load i32, ptr %n.addr.2, align 4
  %t12 = call i64 @i64(i32 %t11)
  %t13 = call ptr @arena-strndup(ptr %t10, i64 %t12)
  ret ptr %t13
}

define ptr @sanitize-for-ir(ptr %name.arg) {
entry:
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %n.addr.0 = alloca i64, align 8
  %s.addr.3 = alloca ptr, align 8
  %i.addr.8 = alloca i64, align 8
  %c.addr.13 = alloca i32, align 4
  %is-digit.addr.20 = alloca i1, align 1
  %is-lower.addr.24 = alloca i1, align 1
  %and.val1 = alloca i1, align 1
  %is-upper.addr.30 = alloca i1, align 1
  %and.val2 = alloca i1, align 1
  %is-safe.addr.36 = alloca i1, align 1
  %or.val3 = alloca i1, align 1
  %ok.addr.42 = alloca i1, align 1
  %or.val4 = alloca i1, align 1
  %or.val5 = alloca i1, align 1
  %or.val6 = alloca i1, align 1
  %t1 = load ptr, ptr %name.addr, align 8
  %t2 = call i64 @strlen(ptr %t1)
  store i64 %t2, ptr %n.addr.0, align 8
  %t4 = load i64, ptr %n.addr.0, align 8
  %t5 = sext i32 1 to i64
  %t6 = add nsw i64 %t4, %t5
  %t7 = call ptr @arena-alloc(i64 %t6)
  store ptr %t7, ptr %s.addr.3, align 8
  %t9 = sext i32 0 to i64
  store i64 %t9, ptr %i.addr.8, align 8
  br label %while.cond0
while.cond0:
  %t10 = load i64, ptr %i.addr.8, align 8
  %t11 = load i64, ptr %n.addr.0, align 8
  %t12 = icmp slt i64 %t10, %t11
  br i1 %t12, label %while.body0, label %while.end0
while.body0:
  %t14 = load ptr, ptr %name.addr, align 8
  %t15 = load i64, ptr %i.addr.8, align 8
  %t16 = getelementptr inbounds i8, ptr %t14, i64 %t15
  %t17 = load i8, ptr %t16, align 1
  %t18 = sext i8 %t17 to i32
  %t19 = and i32 %t18, 255
  store i32 %t19, ptr %c.addr.13, align 4
  %t21 = load i32, ptr %c.addr.13, align 4
  %t22 = call i32 @isdigit(i32 %t21)
  %t23 = icmp ne i32 %t22, 0
  store i1 %t23, ptr %is-digit.addr.20, align 1
  %t25 = load i32, ptr %c.addr.13, align 4
  %t26 = icmp sge i32 %t25, 97
  store i1 %t26, ptr %and.val1, align 1
  br i1 %t26, label %and.rhs1, label %and.end1
and.rhs1:
  %t27 = load i32, ptr %c.addr.13, align 4
  %t28 = icmp sle i32 %t27, 122
  store i1 %t28, ptr %and.val1, align 1
  br label %and.end1
and.end1:
  %t29 = load i1, ptr %and.val1, align 1
  store i1 %t29, ptr %is-lower.addr.24, align 1
  %t31 = load i32, ptr %c.addr.13, align 4
  %t32 = icmp sge i32 %t31, 65
  store i1 %t32, ptr %and.val2, align 1
  br i1 %t32, label %and.rhs2, label %and.end2
and.rhs2:
  %t33 = load i32, ptr %c.addr.13, align 4
  %t34 = icmp sle i32 %t33, 90
  store i1 %t34, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t35 = load i1, ptr %and.val2, align 1
  store i1 %t35, ptr %is-upper.addr.30, align 1
  %t37 = load i32, ptr %c.addr.13, align 4
  %t38 = icmp eq i32 %t37, 95
  store i1 %t38, ptr %or.val3, align 1
  br i1 %t38, label %or.end3, label %or.rhs3
or.rhs3:
  %t39 = load i32, ptr %c.addr.13, align 4
  %t40 = icmp eq i32 %t39, 46
  store i1 %t40, ptr %or.val3, align 1
  br label %or.end3
or.end3:
  %t41 = load i1, ptr %or.val3, align 1
  store i1 %t41, ptr %is-safe.addr.36, align 1
  %t43 = load i1, ptr %is-digit.addr.20, align 1
  store i1 %t43, ptr %or.val4, align 1
  br i1 %t43, label %or.end4, label %or.rhs4
or.rhs4:
  %t44 = load i1, ptr %is-lower.addr.24, align 1
  store i1 %t44, ptr %or.val5, align 1
  br i1 %t44, label %or.end5, label %or.rhs5
or.rhs5:
  %t45 = load i1, ptr %is-upper.addr.30, align 1
  store i1 %t45, ptr %or.val6, align 1
  br i1 %t45, label %or.end6, label %or.rhs6
or.rhs6:
  %t46 = load i1, ptr %is-safe.addr.36, align 1
  store i1 %t46, ptr %or.val6, align 1
  br label %or.end6
or.end6:
  %t47 = load i1, ptr %or.val6, align 1
  store i1 %t47, ptr %or.val5, align 1
  br label %or.end5
or.end5:
  %t48 = load i1, ptr %or.val5, align 1
  store i1 %t48, ptr %or.val4, align 1
  br label %or.end4
or.end4:
  %t49 = load i1, ptr %or.val4, align 1
  store i1 %t49, ptr %ok.addr.42, align 1
  %t50 = load i1, ptr %ok.addr.42, align 1
  br i1 %t50, label %cond.then7.0, label %cond.test7.1
cond.then7.0:
  %t51 = load ptr, ptr %s.addr.3, align 8
  %t52 = load i64, ptr %i.addr.8, align 8
  %t53 = load i32, ptr %c.addr.13, align 4
  %t54 = trunc i32 %t53 to i8
  %t55 = getelementptr inbounds i8, ptr %t51, i64 %t52
  store i8 %t54, ptr %t55, align 1
  br label %cond.end7
cond.test7.1:
  br i1 1, label %cond.then7.1, label %cond.end7
cond.then7.1:
  %t56 = load ptr, ptr %s.addr.3, align 8
  %t57 = load i64, ptr %i.addr.8, align 8
  %t58 = trunc i32 95 to i8
  %t59 = getelementptr inbounds i8, ptr %t56, i64 %t57
  store i8 %t58, ptr %t59, align 1
  br label %cond.end7
cond.end7:
  %t60 = load i64, ptr %i.addr.8, align 8
  %t61 = sext i32 1 to i64
  %t62 = add nsw i64 %t60, %t61
  store i64 %t62, ptr %i.addr.8, align 8
  br label %while.cond0
while.end0:
  %t63 = load ptr, ptr %s.addr.3, align 8
  %t64 = load i64, ptr %n.addr.0, align 8
  %t65 = trunc i32 0 to i8
  %t66 = getelementptr inbounds i8, ptr %t63, i64 %t64
  store i8 %t65, ptr %t66, align 1
  %t67 = load ptr, ptr %s.addr.3, align 8
  ret ptr %t67
}

define ptr @alloc-tok() {
entry:
  %t0 = getelementptr %Tok, ptr null, i32 1
  %t1 = ptrtoint ptr %t0 to i64
  %t2 = call ptr @arena-alloc(i64 %t1)
  ret ptr %t2
}

define ptr @alloc-node() {
entry:
  %t0 = getelementptr %Node, ptr null, i32 1
  %t1 = ptrtoint ptr %t0 to i64
  %t2 = call ptr @arena-alloc(i64 %t1)
  ret ptr %t2
}

define ptr @nucleus_gensym() {
entry:
  %id.addr.0 = alloca i32, align 4
  %buf.addr.4 = alloca ptr, align 8
  %n.addr.7 = alloca ptr, align 8
  %t1 = load i32, ptr @g-gensym-id, align 4
  store i32 %t1, ptr %id.addr.0, align 4
  %t2 = load i32, ptr @g-gensym-id, align 4
  %t3 = add nsw i32 %t2, 1
  store i32 %t3, ptr @g-gensym-id, align 4
  %t5 = sext i32 32 to i64
  %t6 = call ptr @malloc(i64 %t5)
  store ptr %t6, ptr %buf.addr.4, align 8
  %t8 = getelementptr %Node, ptr null, i32 1
  %t9 = ptrtoint ptr %t8 to i64
  %t10 = call ptr @malloc(i64 %t9)
  store ptr %t10, ptr %n.addr.7, align 8
  %t11 = load ptr, ptr %buf.addr.4, align 8
  %t12 = sext i32 32 to i64
  %t13 = getelementptr inbounds [8 x i8], ptr @.str.18, i64 0, i64 0
  %t14 = load i32, ptr %id.addr.0, align 4
  %t15 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t11, i64 %t12, ptr %t13, i32 %t14)
  %t16 = load ptr, ptr %n.addr.7, align 8
  %t17 = getelementptr %Node, ptr null, i32 1
  %t18 = ptrtoint ptr %t17 to i64
  %t19 = call ptr @memset(ptr %t16, i32 0, i64 %t18)
  %t20 = load ptr, ptr %n.addr.7, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 0
  store i32 2, ptr %t21, align 4
  %t22 = load ptr, ptr %n.addr.7, align 8
  %t23 = load ptr, ptr %buf.addr.4, align 8
  %t24 = getelementptr inbounds %Node, ptr %t22, i32 0, i32 3
  store ptr %t23, ptr %t24, align 8
  %t25 = load ptr, ptr %n.addr.7, align 8
  ret ptr %t25
}

define ptr @alloc-type() {
entry:
  %t.addr.0 = alloca ptr, align 8
  %t1 = getelementptr %Type, ptr null, i32 1
  %t2 = ptrtoint ptr %t1 to i64
  %t3 = call ptr @arena-alloc(i64 %t2)
  store ptr %t3, ptr %t.addr.0, align 8
  %t4 = load ptr, ptr %t.addr.0, align 8
  ret ptr %t4
}

define ptr @alloc-val(ptr %ty.arg, ptr %v.arg) {
entry:
  %ty.addr = alloca ptr, align 8
  store ptr %ty.arg, ptr %ty.addr, align 8
  %v.addr = alloca ptr, align 8
  store ptr %v.arg, ptr %v.addr, align 8
  %r.addr.0 = alloca ptr, align 8
  %t1 = getelementptr %Val, ptr null, i32 1
  %t2 = ptrtoint ptr %t1 to i64
  %t3 = call ptr @arena-alloc(i64 %t2)
  store ptr %t3, ptr %r.addr.0, align 8
  %t4 = load ptr, ptr %r.addr.0, align 8
  %t5 = load ptr, ptr %ty.addr, align 8
  %t6 = getelementptr inbounds %Val, ptr %t4, i32 0, i32 0
  store ptr %t5, ptr %t6, align 8
  %t7 = load ptr, ptr %r.addr.0, align 8
  %t8 = load ptr, ptr %v.addr, align 8
  %t9 = getelementptr inbounds %Val, ptr %t7, i32 0, i32 1
  store ptr %t8, ptr %t9, align 8
  %t10 = load ptr, ptr %r.addr.0, align 8
  ret ptr %t10
}

define ptr @make-vec() {
entry:
  %t0 = getelementptr %Vec, ptr null, i32 1
  %t1 = ptrtoint ptr %t0 to i64
  %t2 = call ptr @arena-alloc(i64 %t1)
  ret ptr %t2
}

define void @vec-push(ptr %v.arg, ptr %item.arg) {
entry:
  %v.addr = alloca ptr, align 8
  store ptr %v.arg, ptr %v.addr, align 8
  %item.addr = alloca ptr, align 8
  store ptr %item.arg, ptr %item.addr, align 8
  %vv.addr.0 = alloca ptr, align 8
  %nc.addr.9 = alloca i32, align 4
  %nd.addr.18 = alloca ptr, align 8
  %t1 = load ptr, ptr %v.addr, align 8
  store ptr %t1, ptr %vv.addr.0, align 8
  %t2 = load ptr, ptr %vv.addr.0, align 8
  %t3 = getelementptr inbounds %Vec, ptr %t2, i32 0, i32 1
  %t4 = load i32, ptr %t3, align 4
  %t5 = load ptr, ptr %vv.addr.0, align 8
  %t6 = getelementptr inbounds %Vec, ptr %t5, i32 0, i32 2
  %t7 = load i32, ptr %t6, align 4
  %t8 = icmp eq i32 %t4, %t7
  br i1 %t8, label %cond.then0.0, label %cond.end0
cond.then0.0:
  store i32 4, ptr %nc.addr.9, align 4
  %t10 = load ptr, ptr %vv.addr.0, align 8
  %t11 = getelementptr inbounds %Vec, ptr %t10, i32 0, i32 2
  %t12 = load i32, ptr %t11, align 4
  %t13 = icmp ne i32 %t12, 0
  br i1 %t13, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t14 = load ptr, ptr %vv.addr.0, align 8
  %t15 = getelementptr inbounds %Vec, ptr %t14, i32 0, i32 2
  %t16 = load i32, ptr %t15, align 4
  %t17 = mul nsw i32 %t16, 2
  store i32 %t17, ptr %nc.addr.9, align 4
  br label %cond.end1
cond.end1:
  %t19 = load i32, ptr %nc.addr.9, align 4
  %t20 = call i64 @i64(i32 %t19)
  %t21 = call i64 @i64(i32 8)
  %t22 = mul nsw i64 %t20, %t21
  %t23 = call ptr @arena-alloc(i64 %t22)
  store ptr %t23, ptr %nd.addr.18, align 8
  %t24 = load ptr, ptr %vv.addr.0, align 8
  %t25 = getelementptr inbounds %Vec, ptr %t24, i32 0, i32 1
  %t26 = load i32, ptr %t25, align 4
  %t27 = icmp ne i32 %t26, 0
  br i1 %t27, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t28 = load ptr, ptr %nd.addr.18, align 8
  %t29 = load ptr, ptr %vv.addr.0, align 8
  %t30 = getelementptr inbounds %Vec, ptr %t29, i32 0, i32 0
  %t31 = load ptr, ptr %t30, align 8
  %t32 = load ptr, ptr %vv.addr.0, align 8
  %t33 = getelementptr inbounds %Vec, ptr %t32, i32 0, i32 1
  %t34 = load i32, ptr %t33, align 4
  %t35 = call i64 @i64(i32 %t34)
  %t36 = call i64 @i64(i32 8)
  %t37 = mul nsw i64 %t35, %t36
  %t38 = call ptr @memcpy(ptr %t28, ptr %t31, i64 %t37)
  br label %cond.end2
cond.end2:
  %t39 = load ptr, ptr %vv.addr.0, align 8
  %t40 = load ptr, ptr %nd.addr.18, align 8
  %t41 = getelementptr inbounds %Vec, ptr %t39, i32 0, i32 0
  store ptr %t40, ptr %t41, align 8
  %t42 = load ptr, ptr %vv.addr.0, align 8
  %t43 = load i32, ptr %nc.addr.9, align 4
  %t44 = getelementptr inbounds %Vec, ptr %t42, i32 0, i32 2
  store i32 %t43, ptr %t44, align 4
  br label %cond.end0
cond.end0:
  %t45 = load ptr, ptr %vv.addr.0, align 8
  %t46 = getelementptr inbounds %Vec, ptr %t45, i32 0, i32 0
  %t47 = load ptr, ptr %t46, align 8
  %t48 = load ptr, ptr %vv.addr.0, align 8
  %t49 = getelementptr inbounds %Vec, ptr %t48, i32 0, i32 1
  %t50 = load i32, ptr %t49, align 4
  %t51 = sext i32 %t50 to i64
  %t52 = load ptr, ptr %item.addr, align 8
  %t53 = getelementptr inbounds ptr, ptr %t47, i64 %t51
  store ptr %t52, ptr %t53, align 8
  %t54 = load ptr, ptr %vv.addr.0, align 8
  %t55 = load ptr, ptr %vv.addr.0, align 8
  %t56 = getelementptr inbounds %Vec, ptr %t55, i32 0, i32 1
  %t57 = load i32, ptr %t56, align 4
  %t58 = add nsw i32 %t57, 1
  %t59 = getelementptr inbounds %Vec, ptr %t54, i32 0, i32 1
  store i32 %t58, ptr %t59, align 4
  ret void
}

define i32 @char-at(ptr %s.arg, i64 %pos.arg) {
entry:
  %s.addr = alloca ptr, align 8
  store ptr %s.arg, ptr %s.addr, align 8
  %pos.addr = alloca i64, align 8
  store i64 %pos.arg, ptr %pos.addr, align 8
  %t0 = load ptr, ptr %s.addr, align 8
  %t1 = load i64, ptr %pos.addr, align 8
  %t2 = getelementptr inbounds i8, ptr %t0, i64 %t1
  %t3 = load i8, ptr %t2, align 1
  %t4 = sext i8 %t3 to i32
  %t5 = and i32 %t4, 255
  ret i32 %t5
}

define ptr @node-at(ptr %n.arg, i32 %i.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %i.addr = alloca i32, align 4
  store i32 %i.arg, ptr %i.addr, align 4
  %nn.addr.0 = alloca ptr, align 8
  %and.val1 = alloca i1, align 1
  %and.val2 = alloca i1, align 1
  %and.val4 = alloca i1, align 1
  %t1 = load ptr, ptr %n.addr, align 8
  store ptr %t1, ptr %nn.addr.0, align 8
  br label %while.cond0
while.cond0:
  %t2 = load ptr, ptr %n.addr, align 8
  %t3 = icmp ne ptr %t2, null
  store i1 %t3, ptr %and.val2, align 1
  br i1 %t3, label %and.rhs2, label %and.end2
and.rhs2:
  %t4 = load ptr, ptr %nn.addr.0, align 8
  %t5 = getelementptr inbounds %Node, ptr %t4, i32 0, i32 0
  %t6 = load i32, ptr %t5, align 4
  %t7 = icmp eq i32 %t6, 3
  store i1 %t7, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t8 = load i1, ptr %and.val2, align 1
  store i1 %t8, ptr %and.val1, align 1
  br i1 %t8, label %and.rhs1, label %and.end1
and.rhs1:
  %t9 = load i32, ptr %i.addr, align 4
  %t10 = icmp sgt i32 %t9, 0
  store i1 %t10, ptr %and.val1, align 1
  br label %and.end1
and.end1:
  %t11 = load i1, ptr %and.val1, align 1
  br i1 %t11, label %while.body0, label %while.end0
while.body0:
  %t12 = load ptr, ptr %nn.addr.0, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 5
  %t14 = load ptr, ptr %t13, align 8
  store ptr %t14, ptr %n.addr, align 8
  %t15 = load ptr, ptr %n.addr, align 8
  store ptr %t15, ptr %nn.addr.0, align 8
  %t16 = load i32, ptr %i.addr, align 4
  %t17 = sub nsw i32 %t16, 1
  store i32 %t17, ptr %i.addr, align 4
  br label %while.cond0
while.end0:
  %t18 = load ptr, ptr %n.addr, align 8
  %t19 = icmp ne ptr %t18, null
  store i1 %t19, ptr %and.val4, align 1
  br i1 %t19, label %and.rhs4, label %and.end4
and.rhs4:
  %t20 = load ptr, ptr %nn.addr.0, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 0
  %t22 = load i32, ptr %t21, align 4
  %t23 = icmp eq i32 %t22, 3
  store i1 %t23, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t24 = load i1, ptr %and.val4, align 1
  br i1 %t24, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t25 = load ptr, ptr %nn.addr.0, align 8
  %t26 = getelementptr inbounds %Node, ptr %t25, i32 0, i32 4
  %t27 = load ptr, ptr %t26, align 8
  ret ptr %t27
cond.end3:
  ret ptr null
}

define i32 @node-len(ptr %n.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %k.addr.0 = alloca i32, align 4
  %nn.addr.1 = alloca ptr, align 8
  %and.val1 = alloca i1, align 1
  store i32 0, ptr %k.addr.0, align 4
  %t2 = load ptr, ptr %n.addr, align 8
  store ptr %t2, ptr %nn.addr.1, align 8
  br label %while.cond0
while.cond0:
  %t3 = load ptr, ptr %n.addr, align 8
  %t4 = icmp ne ptr %t3, null
  store i1 %t4, ptr %and.val1, align 1
  br i1 %t4, label %and.rhs1, label %and.end1
and.rhs1:
  %t5 = load ptr, ptr %nn.addr.1, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 0
  %t7 = load i32, ptr %t6, align 4
  %t8 = icmp eq i32 %t7, 3
  store i1 %t8, ptr %and.val1, align 1
  br label %and.end1
and.end1:
  %t9 = load i1, ptr %and.val1, align 1
  br i1 %t9, label %while.body0, label %while.end0
while.body0:
  %t10 = load i32, ptr %k.addr.0, align 4
  %t11 = add nsw i32 %t10, 1
  store i32 %t11, ptr %k.addr.0, align 4
  %t12 = load ptr, ptr %nn.addr.1, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 5
  %t14 = load ptr, ptr %t13, align 8
  store ptr %t14, ptr %n.addr, align 8
  %t15 = load ptr, ptr %n.addr, align 8
  store ptr %t15, ptr %nn.addr.1, align 8
  br label %while.cond0
while.end0:
  %t16 = load i32, ptr %k.addr.0, align 4
  ret i32 %t16
}

define i32 @node-is-list(ptr %n.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %t0 = load ptr, ptr %n.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret i32 1
cond.end0:
  %t2 = load ptr, ptr %n.addr, align 8
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 0
  %t4 = load i32, ptr %t3, align 4
  %t5 = icmp eq i32 %t4, 3
  br i1 %t5, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret i32 1
cond.end1:
  ret i32 0
}

define ptr @make-cell(ptr %car.arg, ptr %cdr.arg, i32 %line.arg) {
entry:
  %car.addr = alloca ptr, align 8
  store ptr %car.arg, ptr %car.addr, align 8
  %cdr.addr = alloca ptr, align 8
  store ptr %cdr.arg, ptr %cdr.addr, align 8
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %c.addr.0 = alloca ptr, align 8
  %t1 = call ptr @alloc-node()
  store ptr %t1, ptr %c.addr.0, align 8
  %t2 = load ptr, ptr %c.addr.0, align 8
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 0
  store i32 3, ptr %t3, align 4
  %t4 = load ptr, ptr %c.addr.0, align 8
  %t5 = load i32, ptr %line.addr, align 4
  %t6 = getelementptr inbounds %Node, ptr %t4, i32 0, i32 1
  store i32 %t5, ptr %t6, align 4
  %t7 = load ptr, ptr %c.addr.0, align 8
  %t8 = load ptr, ptr %car.addr, align 8
  %t9 = getelementptr inbounds %Node, ptr %t7, i32 0, i32 4
  store ptr %t8, ptr %t9, align 8
  %t10 = load ptr, ptr %c.addr.0, align 8
  %t11 = load ptr, ptr %cdr.addr, align 8
  %t12 = getelementptr inbounds %Node, ptr %t10, i32 0, i32 5
  store ptr %t11, ptr %t12, align 8
  %t13 = load ptr, ptr %c.addr.0, align 8
  ret ptr %t13
}

define void @die-at(i32 %line.arg, ptr %msg.arg) {
entry:
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %msg.addr = alloca ptr, align 8
  store ptr %msg.arg, ptr %msg.addr, align 8
  %t0 = load ptr, ptr @stderr, align 8
  %t1 = getelementptr inbounds [18 x i8], ptr @.str.19, i64 0, i64 0
  %t2 = load ptr, ptr @g-source-path, align 8
  %t3 = load i32, ptr %line.addr, align 4
  %t4 = load ptr, ptr %msg.addr, align 8
  %t5 = call i32 (ptr, ptr, ...) @fprintf(ptr %t0, ptr %t1, ptr %t2, i32 %t3, ptr %t4)
  call void @exit(i32 1)
  ret void
}

define i32 @peek-char() {
entry:
  %t0 = load ptr, ptr @g-src, align 8
  %t1 = load i64, ptr @g-pos, align 8
  %t2 = call i32 @char-at(ptr %t0, i64 %t1)
  ret i32 %t2
}

define i32 @next-char() {
entry:
  %c.addr.0 = alloca i32, align 4
  %t1 = call i32 @peek-char()
  store i32 %t1, ptr %c.addr.0, align 4
  %t2 = load i32, ptr %c.addr.0, align 4
  %t3 = icmp eq i32 %t2, 0
  br i1 %t3, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret i32 0
cond.end0:
  %t4 = load i64, ptr @g-pos, align 8
  %t5 = sext i32 1 to i64
  %t6 = add nsw i64 %t4, %t5
  store i64 %t6, ptr @g-pos, align 8
  %t7 = load i32, ptr %c.addr.0, align 4
  %t8 = icmp eq i32 %t7, 10
  br i1 %t8, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t9 = load i32, ptr @g-line, align 4
  %t10 = add nsw i32 %t9, 1
  store i32 %t10, ptr @g-line, align 4
  br label %cond.end1
cond.end1:
  %t11 = load i32, ptr %c.addr.0, align 4
  ret i32 %t11
}

define void @skip-ws() {
entry:
  %c.addr.1 = alloca i32, align 4
  %and.val5 = alloca i1, align 1
  br label %while.cond0
while.cond0:
  %t0 = icmp ne i32 0, 1
  br i1 %t0, label %while.body0, label %while.end0
while.body0:
  %t2 = call i32 @peek-char()
  store i32 %t2, ptr %c.addr.1, align 4
  %t3 = load i32, ptr %c.addr.1, align 4
  %t4 = icmp eq i32 %t3, 0
  br i1 %t4, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret void
cond.end1:
  %t5 = load i32, ptr %c.addr.1, align 4
  %t6 = call i32 @isspace(i32 %t5)
  %t7 = icmp ne i32 %t6, 0
  br i1 %t7, label %cond.then2.0, label %cond.test2.1
cond.then2.0:
  %t8 = call i32 @next-char()
  br label %cond.end2
cond.test2.1:
  br i1 1, label %cond.then2.1, label %cond.end2
cond.then2.1:
  %t9 = load i32, ptr %c.addr.1, align 4
  %t10 = icmp eq i32 %t9, 59
  br i1 %t10, label %cond.then3.0, label %cond.test3.1
cond.then3.0:
  br label %while.cond4
while.cond4:
  %t11 = call i32 @peek-char()
  %t12 = icmp ne i32 %t11, 0
  store i1 %t12, ptr %and.val5, align 1
  br i1 %t12, label %and.rhs5, label %and.end5
and.rhs5:
  %t13 = call i32 @peek-char()
  %t14 = icmp ne i32 %t13, 10
  store i1 %t14, ptr %and.val5, align 1
  br label %and.end5
and.end5:
  %t15 = load i1, ptr %and.val5, align 1
  br i1 %t15, label %while.body4, label %while.end4
while.body4:
  %t16 = call i32 @next-char()
  br label %while.cond4
while.end4:
  br label %cond.end3
cond.test3.1:
  br i1 1, label %cond.then3.1, label %cond.end3
cond.then3.1:
  ret void
cond.end3:
  br label %cond.end2
cond.end2:
  br label %while.cond0
while.end0:
  ret void
}

define i32 @is-sym-char(i32 %c.arg) {
entry:
  %c.addr = alloca i32, align 4
  store i32 %c.arg, ptr %c.addr, align 4
  %t0 = load i32, ptr %c.addr, align 4
  %t1 = icmp eq i32 %t0, 0
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret i32 0
cond.end0:
  %t2 = load i32, ptr %c.addr, align 4
  %t3 = call i32 @isspace(i32 %t2)
  %t4 = icmp ne i32 %t3, 0
  br i1 %t4, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret i32 0
cond.end1:
  %t5 = load i32, ptr %c.addr, align 4
  %t6 = icmp eq i32 %t5, 40
  br i1 %t6, label %cond.then2.0, label %cond.end2
cond.then2.0:
  ret i32 0
cond.end2:
  %t7 = load i32, ptr %c.addr, align 4
  %t8 = icmp eq i32 %t7, 41
  br i1 %t8, label %cond.then3.0, label %cond.end3
cond.then3.0:
  ret i32 0
cond.end3:
  %t9 = load i32, ptr %c.addr, align 4
  %t10 = icmp eq i32 %t9, 34
  br i1 %t10, label %cond.then4.0, label %cond.end4
cond.then4.0:
  ret i32 0
cond.end4:
  %t11 = load i32, ptr %c.addr, align 4
  %t12 = icmp eq i32 %t11, 59
  br i1 %t12, label %cond.then5.0, label %cond.end5
cond.then5.0:
  ret i32 0
cond.end5:
  ret i32 1
}

define ptr @lex-string(i32 %open-line.arg) {
entry:
  %open-line.addr = alloca i32, align 4
  store i32 %open-line.arg, ptr %open-line.addr, align 4
  %buf.addr.0 = alloca ptr, align 8
  %n.addr.2 = alloca i64, align 8
  %done.addr.4 = alloca i32, align 4
  %c.addr.7 = alloca i32, align 4
  %e.addr.17 = alloca i32, align 4
  %handled.addr.19 = alloca i32, align 4
  %t.addr.51 = alloca ptr, align 8
  %t1 = alloca i8, i32 4096, align 1
  store ptr %t1, ptr %buf.addr.0, align 8
  %t3 = sext i32 0 to i64
  store i64 %t3, ptr %n.addr.2, align 8
  store i32 0, ptr %done.addr.4, align 4
  br label %while.cond0
while.cond0:
  %t5 = load i32, ptr %done.addr.4, align 4
  %t6 = icmp eq i32 %t5, 0
  br i1 %t6, label %while.body0, label %while.end0
while.body0:
  %t8 = call i32 @next-char()
  store i32 %t8, ptr %c.addr.7, align 4
  %t9 = load i32, ptr %c.addr.7, align 4
  %t10 = icmp eq i32 %t9, 0
  br i1 %t10, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t11 = load i32, ptr %open-line.addr, align 4
  %t12 = getelementptr inbounds [28 x i8], ptr @.str.20, i64 0, i64 0
  call void @die-at(i32 %t11, ptr %t12)
  br label %cond.end1
cond.end1:
  %t13 = load i32, ptr %c.addr.7, align 4
  %t14 = icmp eq i32 %t13, 34
  br i1 %t14, label %cond.then2.0, label %cond.test2.1
cond.then2.0:
  store i32 1, ptr %done.addr.4, align 4
  br label %cond.end2
cond.test2.1:
  br i1 1, label %cond.then2.1, label %cond.end2
cond.then2.1:
  %t15 = load i32, ptr %c.addr.7, align 4
  %t16 = icmp eq i32 %t15, 92
  br i1 %t16, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t18 = call i32 @next-char()
  store i32 %t18, ptr %e.addr.17, align 4
  store i32 0, ptr %handled.addr.19, align 4
  %t20 = load i32, ptr %e.addr.17, align 4
  %t21 = icmp eq i32 %t20, 110
  br i1 %t21, label %cond.then4.0, label %cond.end4
cond.then4.0:
  store i32 10, ptr %c.addr.7, align 4
  store i32 1, ptr %handled.addr.19, align 4
  br label %cond.end4
cond.end4:
  %t22 = load i32, ptr %e.addr.17, align 4
  %t23 = icmp eq i32 %t22, 116
  br i1 %t23, label %cond.then5.0, label %cond.end5
cond.then5.0:
  store i32 9, ptr %c.addr.7, align 4
  store i32 1, ptr %handled.addr.19, align 4
  br label %cond.end5
cond.end5:
  %t24 = load i32, ptr %e.addr.17, align 4
  %t25 = icmp eq i32 %t24, 114
  br i1 %t25, label %cond.then6.0, label %cond.end6
cond.then6.0:
  store i32 13, ptr %c.addr.7, align 4
  store i32 1, ptr %handled.addr.19, align 4
  br label %cond.end6
cond.end6:
  %t26 = load i32, ptr %e.addr.17, align 4
  %t27 = icmp eq i32 %t26, 48
  br i1 %t27, label %cond.then7.0, label %cond.end7
cond.then7.0:
  store i32 0, ptr %c.addr.7, align 4
  store i32 1, ptr %handled.addr.19, align 4
  br label %cond.end7
cond.end7:
  %t28 = load i32, ptr %e.addr.17, align 4
  %t29 = icmp eq i32 %t28, 92
  br i1 %t29, label %cond.then8.0, label %cond.end8
cond.then8.0:
  store i32 92, ptr %c.addr.7, align 4
  store i32 1, ptr %handled.addr.19, align 4
  br label %cond.end8
cond.end8:
  %t30 = load i32, ptr %e.addr.17, align 4
  %t31 = icmp eq i32 %t30, 34
  br i1 %t31, label %cond.then9.0, label %cond.end9
cond.then9.0:
  store i32 34, ptr %c.addr.7, align 4
  store i32 1, ptr %handled.addr.19, align 4
  br label %cond.end9
cond.end9:
  %t32 = load i32, ptr %handled.addr.19, align 4
  %t33 = icmp eq i32 %t32, 0
  br i1 %t33, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t34 = load i32, ptr @g-line, align 4
  %t35 = getelementptr inbounds [19 x i8], ptr @.str.21, i64 0, i64 0
  %t36 = load i32, ptr %e.addr.17, align 4
  %t37 = call ptr @fmt-i32(ptr %t35, i32 %t36)
  call void @die-at(i32 %t34, ptr %t37)
  br label %cond.end10
cond.end10:
  br label %cond.end3
cond.end3:
  %t38 = load i64, ptr %n.addr.2, align 8
  %t39 = sext i32 4095 to i64
  %t40 = icmp sge i64 %t38, %t39
  br i1 %t40, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t41 = load i32, ptr %open-line.addr, align 4
  %t42 = getelementptr inbounds [24 x i8], ptr @.str.22, i64 0, i64 0
  call void @die-at(i32 %t41, ptr %t42)
  br label %cond.end11
cond.end11:
  %t43 = load ptr, ptr %buf.addr.0, align 8
  %t44 = load i64, ptr %n.addr.2, align 8
  %t45 = load i32, ptr %c.addr.7, align 4
  %t46 = trunc i32 %t45 to i8
  %t47 = getelementptr inbounds i8, ptr %t43, i64 %t44
  store i8 %t46, ptr %t47, align 1
  %t48 = load i64, ptr %n.addr.2, align 8
  %t49 = sext i32 1 to i64
  %t50 = add nsw i64 %t48, %t49
  store i64 %t50, ptr %n.addr.2, align 8
  br label %cond.end2
cond.end2:
  br label %while.cond0
while.end0:
  %t52 = call ptr @alloc-tok()
  store ptr %t52, ptr %t.addr.51, align 8
  %t53 = load ptr, ptr %t.addr.51, align 8
  %t54 = getelementptr inbounds %Tok, ptr %t53, i32 0, i32 0
  store i32 7, ptr %t54, align 4
  %t55 = load ptr, ptr %t.addr.51, align 8
  %t56 = load i32, ptr %open-line.addr, align 4
  %t57 = getelementptr inbounds %Tok, ptr %t55, i32 0, i32 1
  store i32 %t56, ptr %t57, align 4
  %t58 = load ptr, ptr %t.addr.51, align 8
  %t59 = load ptr, ptr %buf.addr.0, align 8
  %t60 = load i64, ptr %n.addr.2, align 8
  %t61 = call ptr @arena-strndup(ptr %t59, i64 %t60)
  %t62 = getelementptr inbounds %Tok, ptr %t58, i32 0, i32 3
  store ptr %t61, ptr %t62, align 8
  %t63 = load ptr, ptr %t.addr.51, align 8
  ret ptr %t63
}

define ptr @lex-atom() {
entry:
  %start-line.addr.0 = alloca i32, align 4
  %start.addr.2 = alloca i64, align 8
  %len.addr.8 = alloca i64, align 8
  %text.addr.12 = alloca ptr, align 8
  %is-int.addr.16 = alloca i32, align 4
  %i0.addr.17 = alloca i64, align 8
  %and.val3 = alloca i1, align 1
  %or.val4 = alloca i1, align 1
  %i.addr.39 = alloca i64, align 8
  %buf.addr.55 = alloca ptr, align 8
  %t.addr.70 = alloca ptr, align 8
  %ts.addr.82 = alloca ptr, align 8
  %t1 = load i32, ptr @g-line, align 4
  store i32 %t1, ptr %start-line.addr.0, align 4
  %t3 = load i64, ptr @g-pos, align 8
  store i64 %t3, ptr %start.addr.2, align 8
  br label %while.cond0
while.cond0:
  %t4 = call i32 @peek-char()
  %t5 = call i32 @is-sym-char(i32 %t4)
  %t6 = icmp ne i32 %t5, 0
  br i1 %t6, label %while.body0, label %while.end0
while.body0:
  %t7 = call i32 @next-char()
  br label %while.cond0
while.end0:
  %t9 = load i64, ptr @g-pos, align 8
  %t10 = load i64, ptr %start.addr.2, align 8
  %t11 = sub nsw i64 %t9, %t10
  store i64 %t11, ptr %len.addr.8, align 8
  %t13 = load ptr, ptr @g-src, align 8
  %t14 = load i64, ptr %start.addr.2, align 8
  %t15 = getelementptr inbounds i8, ptr %t13, i64 %t14
  store ptr %t15, ptr %text.addr.12, align 8
  store i32 1, ptr %is-int.addr.16, align 4
  %t18 = sext i32 0 to i64
  store i64 %t18, ptr %i0.addr.17, align 8
  %t19 = load i64, ptr %len.addr.8, align 8
  %t20 = sext i32 0 to i64
  %t21 = icmp eq i64 %t19, %t20
  br i1 %t21, label %cond.then1.0, label %cond.end1
cond.then1.0:
  store i32 0, ptr %is-int.addr.16, align 4
  br label %cond.end1
cond.end1:
  %t22 = load i64, ptr %len.addr.8, align 8
  %t23 = sext i32 0 to i64
  %t24 = icmp sgt i64 %t22, %t23
  store i1 %t24, ptr %and.val3, align 1
  br i1 %t24, label %and.rhs3, label %and.end3
and.rhs3:
  %t25 = load ptr, ptr %text.addr.12, align 8
  %t26 = sext i32 0 to i64
  %t27 = call i32 @char-at(ptr %t25, i64 %t26)
  %t28 = icmp eq i32 %t27, 45
  store i1 %t28, ptr %or.val4, align 1
  br i1 %t28, label %or.end4, label %or.rhs4
or.rhs4:
  %t29 = load ptr, ptr %text.addr.12, align 8
  %t30 = sext i32 0 to i64
  %t31 = call i32 @char-at(ptr %t29, i64 %t30)
  %t32 = icmp eq i32 %t31, 43
  store i1 %t32, ptr %or.val4, align 1
  br label %or.end4
or.end4:
  %t33 = load i1, ptr %or.val4, align 1
  store i1 %t33, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t34 = load i1, ptr %and.val3, align 1
  br i1 %t34, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t35 = sext i32 1 to i64
  store i64 %t35, ptr %i0.addr.17, align 8
  br label %cond.end2
cond.end2:
  %t36 = load i64, ptr %i0.addr.17, align 8
  %t37 = load i64, ptr %len.addr.8, align 8
  %t38 = icmp eq i64 %t36, %t37
  br i1 %t38, label %cond.then5.0, label %cond.end5
cond.then5.0:
  store i32 0, ptr %is-int.addr.16, align 4
  br label %cond.end5
cond.end5:
  %t40 = load i64, ptr %i0.addr.17, align 8
  store i64 %t40, ptr %i.addr.39, align 8
  br label %while.cond6
while.cond6:
  %t41 = load i64, ptr %i.addr.39, align 8
  %t42 = load i64, ptr %len.addr.8, align 8
  %t43 = icmp slt i64 %t41, %t42
  br i1 %t43, label %while.body6, label %while.end6
while.body6:
  %t44 = load ptr, ptr %text.addr.12, align 8
  %t45 = load i64, ptr %i.addr.39, align 8
  %t46 = call i32 @char-at(ptr %t44, i64 %t45)
  %t47 = call i32 @isdigit(i32 %t46)
  %t48 = icmp eq i32 %t47, 0
  br i1 %t48, label %cond.then7.0, label %cond.test7.1
cond.then7.0:
  store i32 0, ptr %is-int.addr.16, align 4
  %t49 = load i64, ptr %len.addr.8, align 8
  store i64 %t49, ptr %i.addr.39, align 8
  br label %cond.end7
cond.test7.1:
  br i1 1, label %cond.then7.1, label %cond.end7
cond.then7.1:
  %t50 = load i64, ptr %i.addr.39, align 8
  %t51 = sext i32 1 to i64
  %t52 = add nsw i64 %t50, %t51
  store i64 %t52, ptr %i.addr.39, align 8
  br label %cond.end7
cond.end7:
  br label %while.cond6
while.end6:
  %t53 = load i32, ptr %is-int.addr.16, align 4
  %t54 = icmp ne i32 %t53, 0
  br i1 %t54, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t56 = alloca i8, i32 64, align 1
  store ptr %t56, ptr %buf.addr.55, align 8
  %t57 = load i64, ptr %len.addr.8, align 8
  %t58 = sext i32 64 to i64
  %t59 = icmp sge i64 %t57, %t58
  br i1 %t59, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t60 = load i32, ptr %start-line.addr.0, align 4
  %t61 = getelementptr inbounds [25 x i8], ptr @.str.23, i64 0, i64 0
  call void @die-at(i32 %t60, ptr %t61)
  br label %cond.end9
cond.end9:
  %t62 = load ptr, ptr %buf.addr.55, align 8
  %t63 = load ptr, ptr %text.addr.12, align 8
  %t64 = load i64, ptr %len.addr.8, align 8
  %t65 = call ptr @memcpy(ptr %t62, ptr %t63, i64 %t64)
  %t66 = load ptr, ptr %buf.addr.55, align 8
  %t67 = load i64, ptr %len.addr.8, align 8
  %t68 = trunc i32 0 to i8
  %t69 = getelementptr inbounds i8, ptr %t66, i64 %t67
  store i8 %t68, ptr %t69, align 1
  %t71 = call ptr @alloc-tok()
  store ptr %t71, ptr %t.addr.70, align 8
  %t72 = load ptr, ptr %t.addr.70, align 8
  %t73 = getelementptr inbounds %Tok, ptr %t72, i32 0, i32 0
  store i32 6, ptr %t73, align 4
  %t74 = load ptr, ptr %t.addr.70, align 8
  %t75 = load i32, ptr %start-line.addr.0, align 4
  %t76 = getelementptr inbounds %Tok, ptr %t74, i32 0, i32 1
  store i32 %t75, ptr %t76, align 4
  %t77 = load ptr, ptr %t.addr.70, align 8
  %t78 = load ptr, ptr %buf.addr.55, align 8
  %t79 = call i64 @strtol(ptr %t78, ptr null, i32 10)
  %t80 = getelementptr inbounds %Tok, ptr %t77, i32 0, i32 2
  store i64 %t79, ptr %t80, align 8
  %t81 = load ptr, ptr %t.addr.70, align 8
  ret ptr %t81
cond.end8:
  %t83 = call ptr @alloc-tok()
  store ptr %t83, ptr %ts.addr.82, align 8
  %t84 = load ptr, ptr %ts.addr.82, align 8
  %t85 = getelementptr inbounds %Tok, ptr %t84, i32 0, i32 0
  store i32 8, ptr %t85, align 4
  %t86 = load ptr, ptr %ts.addr.82, align 8
  %t87 = load i32, ptr %start-line.addr.0, align 4
  %t88 = getelementptr inbounds %Tok, ptr %t86, i32 0, i32 1
  store i32 %t87, ptr %t88, align 4
  %t89 = load ptr, ptr %ts.addr.82, align 8
  %t90 = load ptr, ptr %text.addr.12, align 8
  %t91 = load i64, ptr %len.addr.8, align 8
  %t92 = call ptr @arena-strndup(ptr %t90, i64 %t91)
  %t93 = getelementptr inbounds %Tok, ptr %t89, i32 0, i32 3
  store ptr %t92, ptr %t93, align 8
  %t94 = load ptr, ptr %ts.addr.82, align 8
  ret ptr %t94
}

define ptr @next-tok() {
entry:
  %c.addr.0 = alloca i32, align 4
  %line.addr.2 = alloca i32, align 4
  %te.addr.6 = alloca ptr, align 8
  %tl.addr.17 = alloca ptr, align 8
  %tr.addr.28 = alloca ptr, align 8
  %tq.addr.39 = alloca ptr, align 8
  %tq.addr.50 = alloca ptr, align 8
  %kind.addr.61 = alloca i32, align 4
  %tq.addr.65 = alloca ptr, align 8
  call void @skip-ws()
  %t1 = call i32 @peek-char()
  store i32 %t1, ptr %c.addr.0, align 4
  %t3 = load i32, ptr @g-line, align 4
  store i32 %t3, ptr %line.addr.2, align 4
  %t4 = load i32, ptr %c.addr.0, align 4
  %t5 = icmp eq i32 %t4, 0
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t7 = call ptr @alloc-tok()
  store ptr %t7, ptr %te.addr.6, align 8
  %t8 = load ptr, ptr %te.addr.6, align 8
  %t9 = getelementptr inbounds %Tok, ptr %t8, i32 0, i32 0
  store i32 9, ptr %t9, align 4
  %t10 = load ptr, ptr %te.addr.6, align 8
  %t11 = load i32, ptr %line.addr.2, align 4
  %t12 = getelementptr inbounds %Tok, ptr %t10, i32 0, i32 1
  store i32 %t11, ptr %t12, align 4
  %t13 = load ptr, ptr %te.addr.6, align 8
  ret ptr %t13
cond.end0:
  %t14 = load i32, ptr %c.addr.0, align 4
  %t15 = icmp eq i32 %t14, 40
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = call i32 @next-char()
  %t18 = call ptr @alloc-tok()
  store ptr %t18, ptr %tl.addr.17, align 8
  %t19 = load ptr, ptr %tl.addr.17, align 8
  %t20 = getelementptr inbounds %Tok, ptr %t19, i32 0, i32 0
  store i32 0, ptr %t20, align 4
  %t21 = load ptr, ptr %tl.addr.17, align 8
  %t22 = load i32, ptr %line.addr.2, align 4
  %t23 = getelementptr inbounds %Tok, ptr %t21, i32 0, i32 1
  store i32 %t22, ptr %t23, align 4
  %t24 = load ptr, ptr %tl.addr.17, align 8
  ret ptr %t24
cond.end1:
  %t25 = load i32, ptr %c.addr.0, align 4
  %t26 = icmp eq i32 %t25, 41
  br i1 %t26, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t27 = call i32 @next-char()
  %t29 = call ptr @alloc-tok()
  store ptr %t29, ptr %tr.addr.28, align 8
  %t30 = load ptr, ptr %tr.addr.28, align 8
  %t31 = getelementptr inbounds %Tok, ptr %t30, i32 0, i32 0
  store i32 1, ptr %t31, align 4
  %t32 = load ptr, ptr %tr.addr.28, align 8
  %t33 = load i32, ptr %line.addr.2, align 4
  %t34 = getelementptr inbounds %Tok, ptr %t32, i32 0, i32 1
  store i32 %t33, ptr %t34, align 4
  %t35 = load ptr, ptr %tr.addr.28, align 8
  ret ptr %t35
cond.end2:
  %t36 = load i32, ptr %c.addr.0, align 4
  %t37 = icmp eq i32 %t36, 39
  br i1 %t37, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t38 = call i32 @next-char()
  %t40 = call ptr @alloc-tok()
  store ptr %t40, ptr %tq.addr.39, align 8
  %t41 = load ptr, ptr %tq.addr.39, align 8
  %t42 = getelementptr inbounds %Tok, ptr %t41, i32 0, i32 0
  store i32 2, ptr %t42, align 4
  %t43 = load ptr, ptr %tq.addr.39, align 8
  %t44 = load i32, ptr %line.addr.2, align 4
  %t45 = getelementptr inbounds %Tok, ptr %t43, i32 0, i32 1
  store i32 %t44, ptr %t45, align 4
  %t46 = load ptr, ptr %tq.addr.39, align 8
  ret ptr %t46
cond.end3:
  %t47 = load i32, ptr %c.addr.0, align 4
  %t48 = icmp eq i32 %t47, 96
  br i1 %t48, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t49 = call i32 @next-char()
  %t51 = call ptr @alloc-tok()
  store ptr %t51, ptr %tq.addr.50, align 8
  %t52 = load ptr, ptr %tq.addr.50, align 8
  %t53 = getelementptr inbounds %Tok, ptr %t52, i32 0, i32 0
  store i32 3, ptr %t53, align 4
  %t54 = load ptr, ptr %tq.addr.50, align 8
  %t55 = load i32, ptr %line.addr.2, align 4
  %t56 = getelementptr inbounds %Tok, ptr %t54, i32 0, i32 1
  store i32 %t55, ptr %t56, align 4
  %t57 = load ptr, ptr %tq.addr.50, align 8
  ret ptr %t57
cond.end4:
  %t58 = load i32, ptr %c.addr.0, align 4
  %t59 = icmp eq i32 %t58, 126
  br i1 %t59, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t60 = call i32 @next-char()
  store i32 4, ptr %kind.addr.61, align 4
  %t62 = call i32 @peek-char()
  %t63 = icmp eq i32 %t62, 64
  br i1 %t63, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t64 = call i32 @next-char()
  store i32 5, ptr %kind.addr.61, align 4
  br label %cond.end6
cond.end6:
  %t66 = call ptr @alloc-tok()
  store ptr %t66, ptr %tq.addr.65, align 8
  %t67 = load ptr, ptr %tq.addr.65, align 8
  %t68 = load i32, ptr %kind.addr.61, align 4
  %t69 = getelementptr inbounds %Tok, ptr %t67, i32 0, i32 0
  store i32 %t68, ptr %t69, align 4
  %t70 = load ptr, ptr %tq.addr.65, align 8
  %t71 = load i32, ptr %line.addr.2, align 4
  %t72 = getelementptr inbounds %Tok, ptr %t70, i32 0, i32 1
  store i32 %t71, ptr %t72, align 4
  %t73 = load ptr, ptr %tq.addr.65, align 8
  ret ptr %t73
cond.end5:
  %t74 = load i32, ptr %c.addr.0, align 4
  %t75 = icmp eq i32 %t74, 34
  br i1 %t75, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t76 = call i32 @next-char()
  %t77 = load i32, ptr %line.addr.2, align 4
  %t78 = call ptr @lex-string(i32 %t77)
  ret ptr %t78
cond.end7:
  %t79 = call ptr @lex-atom()
  ret ptr %t79
}

define ptr @peek-tok() {
entry:
  %t0 = load i32, ptr @g-peek-valid, align 4
  %t1 = icmp eq i32 %t0, 0
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t2 = call ptr @next-tok()
  store ptr %t2, ptr @g-peek, align 8
  store i32 1, ptr @g-peek-valid, align 4
  br label %cond.end0
cond.end0:
  %t3 = load ptr, ptr @g-peek, align 8
  ret ptr %t3
}

define ptr @eat-tok() {
entry:
  %t.addr.0 = alloca ptr, align 8
  %t1 = call ptr @peek-tok()
  store ptr %t1, ptr %t.addr.0, align 8
  store i32 0, ptr @g-peek-valid, align 4
  %t2 = load ptr, ptr %t.addr.0, align 8
  ret ptr %t2
}

define ptr @read-form() {
entry:
  %t.addr.0 = alloca ptr, align 8
  %or.val3 = alloca i1, align 1
  %or.val4 = alloca i1, align 1
  %or.val5 = alloca i1, align 1
  %op.addr.37 = alloca ptr, align 8
  %quoted.addr.54 = alloca ptr, align 8
  %sym.addr.56 = alloca ptr, align 8
  %n.addr.82 = alloca ptr, align 8
  %n.addr.101 = alloca ptr, align 8
  %n.addr.120 = alloca ptr, align 8
  %t1 = call ptr @eat-tok()
  store ptr %t1, ptr %t.addr.0, align 8
  %t2 = load ptr, ptr %t.addr.0, align 8
  %t3 = getelementptr inbounds %Tok, ptr %t2, i32 0, i32 0
  %t4 = load i32, ptr %t3, align 4
  %t5 = icmp eq i32 %t4, 0
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t6 = load ptr, ptr %t.addr.0, align 8
  %t7 = getelementptr inbounds %Tok, ptr %t6, i32 0, i32 1
  %t8 = load i32, ptr %t7, align 4
  %t9 = call ptr @read-list(i32 %t8)
  ret ptr %t9
cond.end0:
  %t10 = load ptr, ptr %t.addr.0, align 8
  %t11 = getelementptr inbounds %Tok, ptr %t10, i32 0, i32 0
  %t12 = load i32, ptr %t11, align 4
  %t13 = icmp eq i32 %t12, 1
  br i1 %t13, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t14 = load ptr, ptr %t.addr.0, align 8
  %t15 = getelementptr inbounds %Tok, ptr %t14, i32 0, i32 1
  %t16 = load i32, ptr %t15, align 4
  %t17 = getelementptr inbounds [13 x i8], ptr @.str.24, i64 0, i64 0
  call void @die-at(i32 %t16, ptr %t17)
  br label %cond.end1
cond.end1:
  %t18 = load ptr, ptr %t.addr.0, align 8
  %t19 = getelementptr inbounds %Tok, ptr %t18, i32 0, i32 0
  %t20 = load i32, ptr %t19, align 4
  %t21 = icmp eq i32 %t20, 2
  store i1 %t21, ptr %or.val4, align 1
  br i1 %t21, label %or.end4, label %or.rhs4
or.rhs4:
  %t22 = load ptr, ptr %t.addr.0, align 8
  %t23 = getelementptr inbounds %Tok, ptr %t22, i32 0, i32 0
  %t24 = load i32, ptr %t23, align 4
  %t25 = icmp eq i32 %t24, 3
  store i1 %t25, ptr %or.val4, align 1
  br label %or.end4
or.end4:
  %t26 = load i1, ptr %or.val4, align 1
  store i1 %t26, ptr %or.val3, align 1
  br i1 %t26, label %or.end3, label %or.rhs3
or.rhs3:
  %t27 = load ptr, ptr %t.addr.0, align 8
  %t28 = getelementptr inbounds %Tok, ptr %t27, i32 0, i32 0
  %t29 = load i32, ptr %t28, align 4
  %t30 = icmp eq i32 %t29, 4
  store i1 %t30, ptr %or.val5, align 1
  br i1 %t30, label %or.end5, label %or.rhs5
or.rhs5:
  %t31 = load ptr, ptr %t.addr.0, align 8
  %t32 = getelementptr inbounds %Tok, ptr %t31, i32 0, i32 0
  %t33 = load i32, ptr %t32, align 4
  %t34 = icmp eq i32 %t33, 5
  store i1 %t34, ptr %or.val5, align 1
  br label %or.end5
or.end5:
  %t35 = load i1, ptr %or.val5, align 1
  store i1 %t35, ptr %or.val3, align 1
  br label %or.end3
or.end3:
  %t36 = load i1, ptr %or.val3, align 1
  br i1 %t36, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t38 = getelementptr inbounds [6 x i8], ptr @.str.25, i64 0, i64 0
  store ptr %t38, ptr %op.addr.37, align 8
  %t39 = load ptr, ptr %t.addr.0, align 8
  %t40 = getelementptr inbounds %Tok, ptr %t39, i32 0, i32 0
  %t41 = load i32, ptr %t40, align 4
  %t42 = icmp eq i32 %t41, 3
  br i1 %t42, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t43 = getelementptr inbounds [11 x i8], ptr @.str.26, i64 0, i64 0
  store ptr %t43, ptr %op.addr.37, align 8
  br label %cond.end6
cond.end6:
  %t44 = load ptr, ptr %t.addr.0, align 8
  %t45 = getelementptr inbounds %Tok, ptr %t44, i32 0, i32 0
  %t46 = load i32, ptr %t45, align 4
  %t47 = icmp eq i32 %t46, 4
  br i1 %t47, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t48 = getelementptr inbounds [8 x i8], ptr @.str.27, i64 0, i64 0
  store ptr %t48, ptr %op.addr.37, align 8
  br label %cond.end7
cond.end7:
  %t49 = load ptr, ptr %t.addr.0, align 8
  %t50 = getelementptr inbounds %Tok, ptr %t49, i32 0, i32 0
  %t51 = load i32, ptr %t50, align 4
  %t52 = icmp eq i32 %t51, 5
  br i1 %t52, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t53 = getelementptr inbounds [15 x i8], ptr @.str.28, i64 0, i64 0
  store ptr %t53, ptr %op.addr.37, align 8
  br label %cond.end8
cond.end8:
  %t55 = call ptr @read-form()
  store ptr %t55, ptr %quoted.addr.54, align 8
  %t57 = call ptr @alloc-node()
  store ptr %t57, ptr %sym.addr.56, align 8
  %t58 = load ptr, ptr %sym.addr.56, align 8
  %t59 = getelementptr inbounds %Node, ptr %t58, i32 0, i32 0
  store i32 2, ptr %t59, align 4
  %t60 = load ptr, ptr %sym.addr.56, align 8
  %t61 = load ptr, ptr %t.addr.0, align 8
  %t62 = getelementptr inbounds %Tok, ptr %t61, i32 0, i32 1
  %t63 = load i32, ptr %t62, align 4
  %t64 = getelementptr inbounds %Node, ptr %t60, i32 0, i32 1
  store i32 %t63, ptr %t64, align 4
  %t65 = load ptr, ptr %sym.addr.56, align 8
  %t66 = load ptr, ptr %op.addr.37, align 8
  %t67 = getelementptr inbounds %Node, ptr %t65, i32 0, i32 3
  store ptr %t66, ptr %t67, align 8
  %t68 = load ptr, ptr %sym.addr.56, align 8
  %t69 = load ptr, ptr %quoted.addr.54, align 8
  %t70 = load ptr, ptr %t.addr.0, align 8
  %t71 = getelementptr inbounds %Tok, ptr %t70, i32 0, i32 1
  %t72 = load i32, ptr %t71, align 4
  %t73 = call ptr @make-cell(ptr %t69, ptr null, i32 %t72)
  %t74 = load ptr, ptr %t.addr.0, align 8
  %t75 = getelementptr inbounds %Tok, ptr %t74, i32 0, i32 1
  %t76 = load i32, ptr %t75, align 4
  %t77 = call ptr @make-cell(ptr %t68, ptr %t73, i32 %t76)
  ret ptr %t77
cond.end2:
  %t78 = load ptr, ptr %t.addr.0, align 8
  %t79 = getelementptr inbounds %Tok, ptr %t78, i32 0, i32 0
  %t80 = load i32, ptr %t79, align 4
  %t81 = icmp eq i32 %t80, 6
  br i1 %t81, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t83 = call ptr @alloc-node()
  store ptr %t83, ptr %n.addr.82, align 8
  %t84 = load ptr, ptr %n.addr.82, align 8
  %t85 = getelementptr inbounds %Node, ptr %t84, i32 0, i32 0
  store i32 0, ptr %t85, align 4
  %t86 = load ptr, ptr %n.addr.82, align 8
  %t87 = load ptr, ptr %t.addr.0, align 8
  %t88 = getelementptr inbounds %Tok, ptr %t87, i32 0, i32 1
  %t89 = load i32, ptr %t88, align 4
  %t90 = getelementptr inbounds %Node, ptr %t86, i32 0, i32 1
  store i32 %t89, ptr %t90, align 4
  %t91 = load ptr, ptr %n.addr.82, align 8
  %t92 = load ptr, ptr %t.addr.0, align 8
  %t93 = getelementptr inbounds %Tok, ptr %t92, i32 0, i32 2
  %t94 = load i64, ptr %t93, align 8
  %t95 = getelementptr inbounds %Node, ptr %t91, i32 0, i32 2
  store i64 %t94, ptr %t95, align 8
  %t96 = load ptr, ptr %n.addr.82, align 8
  ret ptr %t96
cond.end9:
  %t97 = load ptr, ptr %t.addr.0, align 8
  %t98 = getelementptr inbounds %Tok, ptr %t97, i32 0, i32 0
  %t99 = load i32, ptr %t98, align 4
  %t100 = icmp eq i32 %t99, 7
  br i1 %t100, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t102 = call ptr @alloc-node()
  store ptr %t102, ptr %n.addr.101, align 8
  %t103 = load ptr, ptr %n.addr.101, align 8
  %t104 = getelementptr inbounds %Node, ptr %t103, i32 0, i32 0
  store i32 1, ptr %t104, align 4
  %t105 = load ptr, ptr %n.addr.101, align 8
  %t106 = load ptr, ptr %t.addr.0, align 8
  %t107 = getelementptr inbounds %Tok, ptr %t106, i32 0, i32 1
  %t108 = load i32, ptr %t107, align 4
  %t109 = getelementptr inbounds %Node, ptr %t105, i32 0, i32 1
  store i32 %t108, ptr %t109, align 4
  %t110 = load ptr, ptr %n.addr.101, align 8
  %t111 = load ptr, ptr %t.addr.0, align 8
  %t112 = getelementptr inbounds %Tok, ptr %t111, i32 0, i32 3
  %t113 = load ptr, ptr %t112, align 8
  %t114 = getelementptr inbounds %Node, ptr %t110, i32 0, i32 3
  store ptr %t113, ptr %t114, align 8
  %t115 = load ptr, ptr %n.addr.101, align 8
  ret ptr %t115
cond.end10:
  %t116 = load ptr, ptr %t.addr.0, align 8
  %t117 = getelementptr inbounds %Tok, ptr %t116, i32 0, i32 0
  %t118 = load i32, ptr %t117, align 4
  %t119 = icmp eq i32 %t118, 8
  br i1 %t119, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t121 = call ptr @alloc-node()
  store ptr %t121, ptr %n.addr.120, align 8
  %t122 = load ptr, ptr %n.addr.120, align 8
  %t123 = getelementptr inbounds %Node, ptr %t122, i32 0, i32 0
  store i32 2, ptr %t123, align 4
  %t124 = load ptr, ptr %n.addr.120, align 8
  %t125 = load ptr, ptr %t.addr.0, align 8
  %t126 = getelementptr inbounds %Tok, ptr %t125, i32 0, i32 1
  %t127 = load i32, ptr %t126, align 4
  %t128 = getelementptr inbounds %Node, ptr %t124, i32 0, i32 1
  store i32 %t127, ptr %t128, align 4
  %t129 = load ptr, ptr %n.addr.120, align 8
  %t130 = load ptr, ptr %t.addr.0, align 8
  %t131 = getelementptr inbounds %Tok, ptr %t130, i32 0, i32 3
  %t132 = load ptr, ptr %t131, align 8
  %t133 = getelementptr inbounds %Node, ptr %t129, i32 0, i32 3
  store ptr %t132, ptr %t133, align 8
  %t134 = load ptr, ptr %n.addr.120, align 8
  ret ptr %t134
cond.end11:
  %t135 = load ptr, ptr %t.addr.0, align 8
  %t136 = getelementptr inbounds %Tok, ptr %t135, i32 0, i32 1
  %t137 = load i32, ptr %t136, align 4
  %t138 = getelementptr inbounds [24 x i8], ptr @.str.29, i64 0, i64 0
  call void @die-at(i32 %t137, ptr %t138)
  ret ptr null
}

define ptr @read-list(i32 %line.arg) {
entry:
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %head.addr.0 = alloca ptr, align 8
  %tail.addr.1 = alloca ptr, align 8
  %t.addr.3 = alloca ptr, align 8
  %child.addr.17 = alloca ptr, align 8
  %cell.addr.19 = alloca ptr, align 8
  store ptr null, ptr %head.addr.0, align 8
  store ptr null, ptr %tail.addr.1, align 8
  br label %while.cond0
while.cond0:
  %t2 = icmp ne i32 0, 1
  br i1 %t2, label %while.body0, label %while.end0
while.body0:
  %t4 = call ptr @peek-tok()
  store ptr %t4, ptr %t.addr.3, align 8
  %t5 = load ptr, ptr %t.addr.3, align 8
  %t6 = getelementptr inbounds %Tok, ptr %t5, i32 0, i32 0
  %t7 = load i32, ptr %t6, align 4
  %t8 = icmp eq i32 %t7, 9
  br i1 %t8, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t9 = load i32, ptr %line.addr, align 4
  %t10 = getelementptr inbounds [18 x i8], ptr @.str.30, i64 0, i64 0
  call void @die-at(i32 %t9, ptr %t10)
  br label %cond.end1
cond.end1:
  %t11 = load ptr, ptr %t.addr.3, align 8
  %t12 = getelementptr inbounds %Tok, ptr %t11, i32 0, i32 0
  %t13 = load i32, ptr %t12, align 4
  %t14 = icmp eq i32 %t13, 1
  br i1 %t14, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t15 = call ptr @eat-tok()
  %t16 = load ptr, ptr %head.addr.0, align 8
  ret ptr %t16
cond.end2:
  %t18 = call ptr @read-form()
  store ptr %t18, ptr %child.addr.17, align 8
  %t20 = load ptr, ptr %child.addr.17, align 8
  %t21 = load i32, ptr %line.addr, align 4
  %t22 = call ptr @make-cell(ptr %t20, ptr null, i32 %t21)
  store ptr %t22, ptr %cell.addr.19, align 8
  %t23 = load ptr, ptr %tail.addr.1, align 8
  %t24 = icmp eq ptr %t23, null
  br i1 %t24, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t25 = load ptr, ptr %cell.addr.19, align 8
  store ptr %t25, ptr %head.addr.0, align 8
  br label %cond.end3
cond.end3:
  %t26 = load ptr, ptr %tail.addr.1, align 8
  %t27 = icmp ne ptr %t26, null
  br i1 %t27, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t28 = load ptr, ptr %tail.addr.1, align 8
  %t29 = load ptr, ptr %cell.addr.19, align 8
  %t30 = getelementptr inbounds %Node, ptr %t28, i32 0, i32 5
  store ptr %t29, ptr %t30, align 8
  br label %cond.end4
cond.end4:
  %t31 = load ptr, ptr %cell.addr.19, align 8
  store ptr %t31, ptr %tail.addr.1, align 8
  br label %while.cond0
while.end0:
  %t32 = load ptr, ptr %head.addr.0, align 8
  ret ptr %t32
}

define ptr @read-program() {
entry:
  %head.addr.0 = alloca ptr, align 8
  %tail.addr.1 = alloca ptr, align 8
  %form.addr.6 = alloca ptr, align 8
  %line.addr.8 = alloca i32, align 4
  %cell.addr.14 = alloca ptr, align 8
  store ptr null, ptr %head.addr.0, align 8
  store ptr null, ptr %tail.addr.1, align 8
  br label %while.cond0
while.cond0:
  %t2 = call ptr @peek-tok()
  %t3 = getelementptr inbounds %Tok, ptr %t2, i32 0, i32 0
  %t4 = load i32, ptr %t3, align 4
  %t5 = icmp ne i32 %t4, 9
  br i1 %t5, label %while.body0, label %while.end0
while.body0:
  %t7 = call ptr @read-form()
  store ptr %t7, ptr %form.addr.6, align 8
  store i32 0, ptr %line.addr.8, align 4
  %t9 = load ptr, ptr %form.addr.6, align 8
  %t10 = icmp ne ptr %t9, null
  br i1 %t10, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t11 = load ptr, ptr %form.addr.6, align 8
  %t12 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 1
  %t13 = load i32, ptr %t12, align 4
  store i32 %t13, ptr %line.addr.8, align 4
  br label %cond.end1
cond.end1:
  %t15 = load ptr, ptr %form.addr.6, align 8
  %t16 = load i32, ptr %line.addr.8, align 4
  %t17 = call ptr @make-cell(ptr %t15, ptr null, i32 %t16)
  store ptr %t17, ptr %cell.addr.14, align 8
  %t18 = load ptr, ptr %tail.addr.1, align 8
  %t19 = icmp eq ptr %t18, null
  br i1 %t19, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t20 = load ptr, ptr %cell.addr.14, align 8
  store ptr %t20, ptr %head.addr.0, align 8
  br label %cond.end2
cond.end2:
  %t21 = load ptr, ptr %tail.addr.1, align 8
  %t22 = icmp ne ptr %t21, null
  br i1 %t22, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t23 = load ptr, ptr %tail.addr.1, align 8
  %t24 = load ptr, ptr %cell.addr.14, align 8
  %t25 = getelementptr inbounds %Node, ptr %t23, i32 0, i32 5
  store ptr %t24, ptr %t25, align 8
  br label %cond.end3
cond.end3:
  %t26 = load ptr, ptr %cell.addr.14, align 8
  store ptr %t26, ptr %tail.addr.1, align 8
  br label %while.cond0
while.end0:
  %t27 = load ptr, ptr %head.addr.0, align 8
  ret ptr %t27
}

define ptr @make-type(i32 %k.arg) {
entry:
  %k.addr = alloca i32, align 4
  store i32 %k.arg, ptr %k.addr, align 4
  %t.addr.0 = alloca ptr, align 8
  %t1 = call ptr @alloc-type()
  store ptr %t1, ptr %t.addr.0, align 8
  %t2 = load ptr, ptr %t.addr.0, align 8
  %t3 = load i32, ptr %k.addr, align 4
  %t4 = getelementptr inbounds %Type, ptr %t2, i32 0, i32 0
  store i32 %t3, ptr %t4, align 4
  %t5 = load ptr, ptr %t.addr.0, align 8
  ret ptr %t5
}

define void @types-init() {
entry:
  %t0 = call ptr @make-type(i32 0)
  store ptr %t0, ptr @ty-void, align 8
  %t1 = call ptr @make-type(i32 1)
  store ptr %t1, ptr @ty-i1, align 8
  %t2 = call ptr @make-type(i32 2)
  store ptr %t2, ptr @ty-i8, align 8
  %t3 = call ptr @make-type(i32 3)
  store ptr %t3, ptr @ty-i16, align 8
  %t4 = call ptr @make-type(i32 4)
  store ptr %t4, ptr @ty-i32, align 8
  %t5 = call ptr @make-type(i32 5)
  store ptr %t5, ptr @ty-i64, align 8
  %t6 = call ptr @make-type(i32 6)
  store ptr %t6, ptr @ty-ptr, align 8
  ret void
}

define ptr @type-to-ir(ptr %t.arg) {
entry:
  %t.addr = alloca ptr, align 8
  store ptr %t.arg, ptr %t.addr, align 8
  %tt.addr.0 = alloca ptr, align 8
  %t1 = load ptr, ptr %t.addr, align 8
  store ptr %t1, ptr %tt.addr.0, align 8
  %t2 = load ptr, ptr %tt.addr.0, align 8
  %t3 = getelementptr inbounds %Type, ptr %t2, i32 0, i32 0
  %t4 = load i32, ptr %t3, align 4
  %t5 = icmp eq i32 %t4, 0
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t6 = getelementptr inbounds [5 x i8], ptr @.str.31, i64 0, i64 0
  ret ptr %t6
cond.end0:
  %t7 = load ptr, ptr %tt.addr.0, align 8
  %t8 = getelementptr inbounds %Type, ptr %t7, i32 0, i32 0
  %t9 = load i32, ptr %t8, align 4
  %t10 = icmp eq i32 %t9, 1
  br i1 %t10, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t11 = getelementptr inbounds [3 x i8], ptr @.str.32, i64 0, i64 0
  ret ptr %t11
cond.end1:
  %t12 = load ptr, ptr %tt.addr.0, align 8
  %t13 = getelementptr inbounds %Type, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp eq i32 %t14, 2
  br i1 %t15, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t16 = getelementptr inbounds [3 x i8], ptr @.str.33, i64 0, i64 0
  ret ptr %t16
cond.end2:
  %t17 = load ptr, ptr %tt.addr.0, align 8
  %t18 = getelementptr inbounds %Type, ptr %t17, i32 0, i32 0
  %t19 = load i32, ptr %t18, align 4
  %t20 = icmp eq i32 %t19, 3
  br i1 %t20, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t21 = getelementptr inbounds [4 x i8], ptr @.str.34, i64 0, i64 0
  ret ptr %t21
cond.end3:
  %t22 = load ptr, ptr %tt.addr.0, align 8
  %t23 = getelementptr inbounds %Type, ptr %t22, i32 0, i32 0
  %t24 = load i32, ptr %t23, align 4
  %t25 = icmp eq i32 %t24, 4
  br i1 %t25, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t26 = getelementptr inbounds [4 x i8], ptr @.str.35, i64 0, i64 0
  ret ptr %t26
cond.end4:
  %t27 = load ptr, ptr %tt.addr.0, align 8
  %t28 = getelementptr inbounds %Type, ptr %t27, i32 0, i32 0
  %t29 = load i32, ptr %t28, align 4
  %t30 = icmp eq i32 %t29, 5
  br i1 %t30, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t31 = getelementptr inbounds [4 x i8], ptr @.str.36, i64 0, i64 0
  ret ptr %t31
cond.end5:
  %t32 = load ptr, ptr %tt.addr.0, align 8
  %t33 = getelementptr inbounds %Type, ptr %t32, i32 0, i32 0
  %t34 = load i32, ptr %t33, align 4
  %t35 = icmp eq i32 %t34, 6
  br i1 %t35, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t36 = getelementptr inbounds [4 x i8], ptr @.str.37, i64 0, i64 0
  ret ptr %t36
cond.end6:
  %t37 = load ptr, ptr %tt.addr.0, align 8
  %t38 = getelementptr inbounds %Type, ptr %t37, i32 0, i32 0
  %t39 = load i32, ptr %t38, align 4
  %t40 = icmp eq i32 %t39, 7
  br i1 %t40, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t41 = getelementptr inbounds [5 x i8], ptr @.str.38, i64 0, i64 0
  ret ptr %t41
cond.end7:
  %t42 = load ptr, ptr %tt.addr.0, align 8
  %t43 = getelementptr inbounds %Type, ptr %t42, i32 0, i32 0
  %t44 = load i32, ptr %t43, align 4
  %t45 = icmp eq i32 %t44, 8
  br i1 %t45, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t46 = getelementptr inbounds [5 x i8], ptr @.str.39, i64 0, i64 0
  %t47 = load ptr, ptr %tt.addr.0, align 8
  %t48 = getelementptr inbounds %Type, ptr %t47, i32 0, i32 6
  %t49 = load ptr, ptr %t48, align 8
  %t50 = getelementptr inbounds %StructDef, ptr %t49, i32 0, i32 0
  %t51 = load ptr, ptr %t50, align 8
  %t52 = call ptr @fmt-s(ptr %t46, ptr %t51)
  ret ptr %t52
cond.end8:
  %t53 = getelementptr inbounds [2 x i8], ptr @.str.40, i64 0, i64 0
  ret ptr %t53
}

define i32 @type-size(ptr %t.arg) {
entry:
  %t.addr = alloca ptr, align 8
  store ptr %t.arg, ptr %t.addr, align 8
  %tt.addr.0 = alloca ptr, align 8
  %t1 = load ptr, ptr %t.addr, align 8
  store ptr %t1, ptr %tt.addr.0, align 8
  %t2 = load ptr, ptr %tt.addr.0, align 8
  %t3 = getelementptr inbounds %Type, ptr %t2, i32 0, i32 0
  %t4 = load i32, ptr %t3, align 4
  %t5 = icmp eq i32 %t4, 1
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret i32 1
cond.end0:
  %t6 = load ptr, ptr %tt.addr.0, align 8
  %t7 = getelementptr inbounds %Type, ptr %t6, i32 0, i32 0
  %t8 = load i32, ptr %t7, align 4
  %t9 = icmp eq i32 %t8, 2
  br i1 %t9, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret i32 1
cond.end1:
  %t10 = load ptr, ptr %tt.addr.0, align 8
  %t11 = getelementptr inbounds %Type, ptr %t10, i32 0, i32 0
  %t12 = load i32, ptr %t11, align 4
  %t13 = icmp eq i32 %t12, 3
  br i1 %t13, label %cond.then2.0, label %cond.end2
cond.then2.0:
  ret i32 2
cond.end2:
  %t14 = load ptr, ptr %tt.addr.0, align 8
  %t15 = getelementptr inbounds %Type, ptr %t14, i32 0, i32 0
  %t16 = load i32, ptr %t15, align 4
  %t17 = icmp eq i32 %t16, 4
  br i1 %t17, label %cond.then3.0, label %cond.end3
cond.then3.0:
  ret i32 4
cond.end3:
  %t18 = load ptr, ptr %tt.addr.0, align 8
  %t19 = getelementptr inbounds %Type, ptr %t18, i32 0, i32 0
  %t20 = load i32, ptr %t19, align 4
  %t21 = icmp eq i32 %t20, 5
  br i1 %t21, label %cond.then4.0, label %cond.end4
cond.then4.0:
  ret i32 8
cond.end4:
  %t22 = load ptr, ptr %tt.addr.0, align 8
  %t23 = getelementptr inbounds %Type, ptr %t22, i32 0, i32 0
  %t24 = load i32, ptr %t23, align 4
  %t25 = icmp eq i32 %t24, 6
  br i1 %t25, label %cond.then5.0, label %cond.end5
cond.then5.0:
  ret i32 8
cond.end5:
  %t26 = load ptr, ptr %tt.addr.0, align 8
  %t27 = getelementptr inbounds %Type, ptr %t26, i32 0, i32 0
  %t28 = load i32, ptr %t27, align 4
  %t29 = icmp eq i32 %t28, 8
  br i1 %t29, label %cond.then6.0, label %cond.end6
cond.then6.0:
  ret i32 8
cond.end6:
  ret i32 1
}

define i32 @is-int-type(ptr %t.arg) {
entry:
  %t.addr = alloca ptr, align 8
  store ptr %t.arg, ptr %t.addr, align 8
  %k.addr.0 = alloca i32, align 4
  %t1 = load ptr, ptr %t.addr, align 8
  %t2 = getelementptr inbounds %Type, ptr %t1, i32 0, i32 0
  %t3 = load i32, ptr %t2, align 4
  store i32 %t3, ptr %k.addr.0, align 4
  %t4 = load i32, ptr %k.addr.0, align 4
  %t5 = icmp eq i32 %t4, 1
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret i32 1
cond.end0:
  %t6 = load i32, ptr %k.addr.0, align 4
  %t7 = icmp eq i32 %t6, 2
  br i1 %t7, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret i32 1
cond.end1:
  %t8 = load i32, ptr %k.addr.0, align 4
  %t9 = icmp eq i32 %t8, 3
  br i1 %t9, label %cond.then2.0, label %cond.end2
cond.then2.0:
  ret i32 1
cond.end2:
  %t10 = load i32, ptr %k.addr.0, align 4
  %t11 = icmp eq i32 %t10, 4
  br i1 %t11, label %cond.then3.0, label %cond.end3
cond.then3.0:
  ret i32 1
cond.end3:
  %t12 = load i32, ptr %k.addr.0, align 4
  %t13 = icmp eq i32 %t12, 5
  br i1 %t13, label %cond.then4.0, label %cond.end4
cond.then4.0:
  ret i32 1
cond.end4:
  ret i32 0
}

define i32 @int-width(ptr %t.arg) {
entry:
  %t.addr = alloca ptr, align 8
  store ptr %t.arg, ptr %t.addr, align 8
  %k.addr.0 = alloca i32, align 4
  %t1 = load ptr, ptr %t.addr, align 8
  %t2 = getelementptr inbounds %Type, ptr %t1, i32 0, i32 0
  %t3 = load i32, ptr %t2, align 4
  store i32 %t3, ptr %k.addr.0, align 4
  %t4 = load i32, ptr %k.addr.0, align 4
  %t5 = icmp eq i32 %t4, 1
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret i32 1
cond.end0:
  %t6 = load i32, ptr %k.addr.0, align 4
  %t7 = icmp eq i32 %t6, 2
  br i1 %t7, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret i32 8
cond.end1:
  %t8 = load i32, ptr %k.addr.0, align 4
  %t9 = icmp eq i32 %t8, 3
  br i1 %t9, label %cond.then2.0, label %cond.end2
cond.then2.0:
  ret i32 16
cond.end2:
  %t10 = load i32, ptr %k.addr.0, align 4
  %t11 = icmp eq i32 %t10, 4
  br i1 %t11, label %cond.then3.0, label %cond.end3
cond.then3.0:
  ret i32 32
cond.end3:
  %t12 = load i32, ptr %k.addr.0, align 4
  %t13 = icmp eq i32 %t12, 5
  br i1 %t13, label %cond.then4.0, label %cond.end4
cond.then4.0:
  ret i32 64
cond.end4:
  ret i32 0
}

define ptr @register-struct(ptr %name.arg) {
entry:
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %sd.addr.5 = alloca ptr, align 8
  %t0 = load i32, ptr @g-structs-len, align 4
  %t1 = icmp sge i32 %t0, 64
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t2 = load ptr, ptr @stderr, align 8
  %t3 = getelementptr inbounds [28 x i8], ptr @.str.41, i64 0, i64 0
  %t4 = call i32 (ptr, ptr, ...) @fprintf(ptr %t2, ptr %t3)
  call void @exit(i32 1)
  br label %cond.end0
cond.end0:
  %t6 = load ptr, ptr @g-structs, align 8
  %t7 = load i32, ptr @g-structs-len, align 4
  %t8 = sext i32 %t7 to i64
  %t9 = getelementptr inbounds %StructDef, ptr %t6, i64 %t8
  store ptr %t9, ptr %sd.addr.5, align 8
  %t10 = load ptr, ptr %sd.addr.5, align 8
  %t11 = load ptr, ptr %name.addr, align 8
  %t12 = getelementptr inbounds %StructDef, ptr %t10, i32 0, i32 0
  store ptr %t11, ptr %t12, align 8
  %t13 = load i32, ptr @g-structs-len, align 4
  %t14 = add nsw i32 %t13, 1
  store i32 %t14, ptr @g-structs-len, align 4
  %t15 = load ptr, ptr %sd.addr.5, align 8
  ret ptr %t15
}

define ptr @lookup-struct(ptr %name.arg) {
entry:
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %i.addr.0 = alloca i32, align 4
  %sd.addr.4 = alloca ptr, align 8
  store i32 0, ptr %i.addr.0, align 4
  br label %while.cond0
while.cond0:
  %t1 = load i32, ptr %i.addr.0, align 4
  %t2 = load i32, ptr @g-structs-len, align 4
  %t3 = icmp slt i32 %t1, %t2
  br i1 %t3, label %while.body0, label %while.end0
while.body0:
  %t5 = load ptr, ptr @g-structs, align 8
  %t6 = load i32, ptr %i.addr.0, align 4
  %t7 = sext i32 %t6 to i64
  %t8 = getelementptr inbounds %StructDef, ptr %t5, i64 %t7
  store ptr %t8, ptr %sd.addr.4, align 8
  %t9 = load ptr, ptr %sd.addr.4, align 8
  %t10 = getelementptr inbounds %StructDef, ptr %t9, i32 0, i32 0
  %t11 = load ptr, ptr %t10, align 8
  %t12 = load ptr, ptr %name.addr, align 8
  %t13 = call i32 @strcmp(ptr %t11, ptr %t12)
  %t14 = icmp eq i32 %t13, 0
  br i1 %t14, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t15 = load ptr, ptr %sd.addr.4, align 8
  ret ptr %t15
cond.end1:
  %t16 = load i32, ptr %i.addr.0, align 4
  %t17 = add nsw i32 %t16, 1
  store i32 %t17, ptr %i.addr.0, align 4
  br label %while.cond0
while.end0:
  ret ptr null
}

define ptr @parse-type-name(ptr %name.arg, i32 %line.arg) {
entry:
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %inner.addr.4 = alloca ptr, align 8
  %p.addr.10 = alloca ptr, align 8
  %sd.addr.61 = alloca ptr, align 8
  %t.addr.66 = alloca ptr, align 8
  %t0 = load ptr, ptr %name.addr, align 8
  %t1 = sext i32 0 to i64
  %t2 = call i32 @char-at(ptr %t0, i64 %t1)
  %t3 = icmp eq i32 %t2, 42
  br i1 %t3, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %name.addr, align 8
  %t6 = sext i32 1 to i64
  %t7 = getelementptr inbounds i8, ptr %t5, i64 %t6
  %t8 = load i32, ptr %line.addr, align 4
  %t9 = call ptr @parse-type-name(ptr %t7, i32 %t8)
  store ptr %t9, ptr %inner.addr.4, align 8
  %t11 = call ptr @make-type(i32 6)
  store ptr %t11, ptr %p.addr.10, align 8
  %t12 = load ptr, ptr %p.addr.10, align 8
  %t13 = load ptr, ptr %inner.addr.4, align 8
  %t14 = getelementptr inbounds %Type, ptr %t12, i32 0, i32 5
  store ptr %t13, ptr %t14, align 8
  %t15 = load ptr, ptr %p.addr.10, align 8
  ret ptr %t15
cond.end0:
  %t16 = load ptr, ptr %name.addr, align 8
  %t17 = getelementptr inbounds [4 x i8], ptr @.str.42, i64 0, i64 0
  %t18 = call i32 @strcmp(ptr %t16, ptr %t17)
  %t19 = icmp eq i32 %t18, 0
  br i1 %t19, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t20 = load ptr, ptr @ty-i32, align 8
  ret ptr %t20
cond.end1:
  %t21 = load ptr, ptr %name.addr, align 8
  %t22 = getelementptr inbounds [3 x i8], ptr @.str.43, i64 0, i64 0
  %t23 = call i32 @strcmp(ptr %t21, ptr %t22)
  %t24 = icmp eq i32 %t23, 0
  br i1 %t24, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t25 = load ptr, ptr @ty-i1, align 8
  ret ptr %t25
cond.end2:
  %t26 = load ptr, ptr %name.addr, align 8
  %t27 = getelementptr inbounds [3 x i8], ptr @.str.44, i64 0, i64 0
  %t28 = call i32 @strcmp(ptr %t26, ptr %t27)
  %t29 = icmp eq i32 %t28, 0
  br i1 %t29, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t30 = load ptr, ptr @ty-i8, align 8
  ret ptr %t30
cond.end3:
  %t31 = load ptr, ptr %name.addr, align 8
  %t32 = getelementptr inbounds [4 x i8], ptr @.str.45, i64 0, i64 0
  %t33 = call i32 @strcmp(ptr %t31, ptr %t32)
  %t34 = icmp eq i32 %t33, 0
  br i1 %t34, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t35 = load ptr, ptr @ty-i16, align 8
  ret ptr %t35
cond.end4:
  %t36 = load ptr, ptr %name.addr, align 8
  %t37 = getelementptr inbounds [4 x i8], ptr @.str.46, i64 0, i64 0
  %t38 = call i32 @strcmp(ptr %t36, ptr %t37)
  %t39 = icmp eq i32 %t38, 0
  br i1 %t39, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t40 = load ptr, ptr @ty-i32, align 8
  ret ptr %t40
cond.end5:
  %t41 = load ptr, ptr %name.addr, align 8
  %t42 = getelementptr inbounds [4 x i8], ptr @.str.47, i64 0, i64 0
  %t43 = call i32 @strcmp(ptr %t41, ptr %t42)
  %t44 = icmp eq i32 %t43, 0
  br i1 %t44, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t45 = load ptr, ptr @ty-i64, align 8
  ret ptr %t45
cond.end6:
  %t46 = load ptr, ptr %name.addr, align 8
  %t47 = getelementptr inbounds [5 x i8], ptr @.str.48, i64 0, i64 0
  %t48 = call i32 @strcmp(ptr %t46, ptr %t47)
  %t49 = icmp eq i32 %t48, 0
  br i1 %t49, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t50 = load ptr, ptr @ty-i1, align 8
  ret ptr %t50
cond.end7:
  %t51 = load ptr, ptr %name.addr, align 8
  %t52 = getelementptr inbounds [4 x i8], ptr @.str.49, i64 0, i64 0
  %t53 = call i32 @strcmp(ptr %t51, ptr %t52)
  %t54 = icmp eq i32 %t53, 0
  br i1 %t54, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t55 = load ptr, ptr @ty-ptr, align 8
  ret ptr %t55
cond.end8:
  %t56 = load ptr, ptr %name.addr, align 8
  %t57 = getelementptr inbounds [5 x i8], ptr @.str.50, i64 0, i64 0
  %t58 = call i32 @strcmp(ptr %t56, ptr %t57)
  %t59 = icmp eq i32 %t58, 0
  br i1 %t59, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t60 = load ptr, ptr @ty-void, align 8
  ret ptr %t60
cond.end9:
  %t62 = load ptr, ptr %name.addr, align 8
  %t63 = call ptr @lookup-struct(ptr %t62)
  store ptr %t63, ptr %sd.addr.61, align 8
  %t64 = load ptr, ptr %sd.addr.61, align 8
  %t65 = icmp ne ptr %t64, null
  br i1 %t65, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t67 = call ptr @make-type(i32 8)
  store ptr %t67, ptr %t.addr.66, align 8
  %t68 = load ptr, ptr %t.addr.66, align 8
  %t69 = load ptr, ptr %sd.addr.61, align 8
  %t70 = getelementptr inbounds %Type, ptr %t68, i32 0, i32 6
  store ptr %t69, ptr %t70, align 8
  %t71 = load ptr, ptr %t.addr.66, align 8
  ret ptr %t71
cond.end10:
  %t72 = load i32, ptr %line.addr, align 4
  %t73 = getelementptr inbounds [17 x i8], ptr @.str.51, i64 0, i64 0
  %t74 = load ptr, ptr %name.addr, align 8
  %t75 = call ptr @fmt-s(ptr %t73, ptr %t74)
  call void @die-at(i32 %t72, ptr %t75)
  ret ptr null
}

define void @split-typed(ptr %sym.arg, ptr %out-name.arg, ptr %out-type-name.arg) {
entry:
  %sym.addr = alloca ptr, align 8
  store ptr %sym.arg, ptr %sym.addr, align 8
  %out-name.addr = alloca ptr, align 8
  store ptr %out-name.arg, ptr %out-name.addr, align 8
  %out-type-name.addr = alloca ptr, align 8
  store ptr %out-type-name.arg, ptr %out-type-name.addr, align 8
  %colon.addr.0 = alloca ptr, align 8
  %name-len.addr.9 = alloca i64, align 8
  %t1 = load ptr, ptr %sym.addr, align 8
  %t2 = call ptr @strchr(ptr %t1, i32 58)
  store ptr %t2, ptr %colon.addr.0, align 8
  %t3 = load ptr, ptr %colon.addr.0, align 8
  %t4 = icmp eq ptr %t3, null
  br i1 %t4, label %cond.then0.0, label %cond.test0.1
cond.then0.0:
  %t5 = load ptr, ptr %out-name.addr, align 8
  %t6 = load ptr, ptr %sym.addr, align 8
  %t7 = call ptr @arena-strdup(ptr %t6)
  store ptr %t7, ptr %t5, align 8
  %t8 = load ptr, ptr %out-type-name.addr, align 8
  store ptr null, ptr %t8, align 8
  br label %cond.end0
cond.test0.1:
  br i1 1, label %cond.then0.1, label %cond.end0
cond.then0.1:
  %t10 = load ptr, ptr %colon.addr.0, align 8
  %t11 = ptrtoint ptr %t10 to i64
  %t12 = load ptr, ptr %sym.addr, align 8
  %t13 = ptrtoint ptr %t12 to i64
  %t14 = sub nsw i64 %t11, %t13
  store i64 %t14, ptr %name-len.addr.9, align 8
  %t15 = load ptr, ptr %out-name.addr, align 8
  %t16 = load ptr, ptr %sym.addr, align 8
  %t17 = load i64, ptr %name-len.addr.9, align 8
  %t18 = call ptr @arena-strndup(ptr %t16, i64 %t17)
  store ptr %t18, ptr %t15, align 8
  %t19 = load ptr, ptr %out-type-name.addr, align 8
  %t20 = load ptr, ptr %colon.addr.0, align 8
  %t21 = sext i32 1 to i64
  %t22 = getelementptr inbounds i8, ptr %t20, i64 %t21
  %t23 = call ptr @arena-strdup(ptr %t22)
  store ptr %t23, ptr %t19, align 8
  br label %cond.end0
cond.end0:
  ret void
}

define ptr @scope-new(ptr %parent.arg) {
entry:
  %parent.addr = alloca ptr, align 8
  store ptr %parent.arg, ptr %parent.addr, align 8
  %s.addr.0 = alloca ptr, align 8
  %t1 = getelementptr %Scope, ptr null, i32 1
  %t2 = ptrtoint ptr %t1 to i64
  %t3 = call ptr @arena-alloc(i64 %t2)
  store ptr %t3, ptr %s.addr.0, align 8
  %t4 = load ptr, ptr %s.addr.0, align 8
  %t5 = load ptr, ptr %parent.addr, align 8
  %t6 = getelementptr inbounds %Scope, ptr %t4, i32 0, i32 0
  store ptr %t5, ptr %t6, align 8
  %t7 = load ptr, ptr %s.addr.0, align 8
  ret ptr %t7
}

define ptr @scope-define(ptr %s.arg, ptr %name.arg, ptr %type.arg, ptr %ir-name.arg, i32 %is-local.arg) {
entry:
  %s.addr = alloca ptr, align 8
  store ptr %s.arg, ptr %s.addr, align 8
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %type.addr = alloca ptr, align 8
  store ptr %type.arg, ptr %type.addr, align 8
  %ir-name.addr = alloca ptr, align 8
  store ptr %ir-name.arg, ptr %ir-name.addr, align 8
  %is-local.addr = alloca i32, align 4
  store i32 %is-local.arg, ptr %is-local.addr, align 4
  %sc.addr.0 = alloca ptr, align 8
  %nc.addr.9 = alloca i32, align 4
  %ns.addr.18 = alloca ptr, align 8
  %sym.addr.47 = alloca ptr, align 8
  %t1 = load ptr, ptr %s.addr, align 8
  store ptr %t1, ptr %sc.addr.0, align 8
  %t2 = load ptr, ptr %sc.addr.0, align 8
  %t3 = getelementptr inbounds %Scope, ptr %t2, i32 0, i32 2
  %t4 = load i32, ptr %t3, align 4
  %t5 = load ptr, ptr %sc.addr.0, align 8
  %t6 = getelementptr inbounds %Scope, ptr %t5, i32 0, i32 3
  %t7 = load i32, ptr %t6, align 4
  %t8 = icmp eq i32 %t4, %t7
  br i1 %t8, label %cond.then0.0, label %cond.end0
cond.then0.0:
  store i32 8, ptr %nc.addr.9, align 4
  %t10 = load ptr, ptr %sc.addr.0, align 8
  %t11 = getelementptr inbounds %Scope, ptr %t10, i32 0, i32 3
  %t12 = load i32, ptr %t11, align 4
  %t13 = icmp ne i32 %t12, 0
  br i1 %t13, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t14 = load ptr, ptr %sc.addr.0, align 8
  %t15 = getelementptr inbounds %Scope, ptr %t14, i32 0, i32 3
  %t16 = load i32, ptr %t15, align 4
  %t17 = mul nsw i32 %t16, 2
  store i32 %t17, ptr %nc.addr.9, align 4
  br label %cond.end1
cond.end1:
  %t19 = load i32, ptr %nc.addr.9, align 4
  %t20 = call i64 @i64(i32 %t19)
  %t21 = getelementptr %Sym, ptr null, i32 1
  %t22 = ptrtoint ptr %t21 to i64
  %t23 = mul nsw i64 %t20, %t22
  %t24 = call ptr @arena-alloc(i64 %t23)
  store ptr %t24, ptr %ns.addr.18, align 8
  %t25 = load ptr, ptr %sc.addr.0, align 8
  %t26 = getelementptr inbounds %Scope, ptr %t25, i32 0, i32 2
  %t27 = load i32, ptr %t26, align 4
  %t28 = icmp ne i32 %t27, 0
  br i1 %t28, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t29 = load ptr, ptr %ns.addr.18, align 8
  %t30 = load ptr, ptr %sc.addr.0, align 8
  %t31 = getelementptr inbounds %Scope, ptr %t30, i32 0, i32 1
  %t32 = load ptr, ptr %t31, align 8
  %t33 = load ptr, ptr %sc.addr.0, align 8
  %t34 = getelementptr inbounds %Scope, ptr %t33, i32 0, i32 2
  %t35 = load i32, ptr %t34, align 4
  %t36 = call i64 @i64(i32 %t35)
  %t37 = getelementptr %Sym, ptr null, i32 1
  %t38 = ptrtoint ptr %t37 to i64
  %t39 = mul nsw i64 %t36, %t38
  %t40 = call ptr @memcpy(ptr %t29, ptr %t32, i64 %t39)
  br label %cond.end2
cond.end2:
  %t41 = load ptr, ptr %sc.addr.0, align 8
  %t42 = load ptr, ptr %ns.addr.18, align 8
  %t43 = getelementptr inbounds %Scope, ptr %t41, i32 0, i32 1
  store ptr %t42, ptr %t43, align 8
  %t44 = load ptr, ptr %sc.addr.0, align 8
  %t45 = load i32, ptr %nc.addr.9, align 4
  %t46 = getelementptr inbounds %Scope, ptr %t44, i32 0, i32 3
  store i32 %t45, ptr %t46, align 4
  br label %cond.end0
cond.end0:
  %t48 = load ptr, ptr %sc.addr.0, align 8
  %t49 = getelementptr inbounds %Scope, ptr %t48, i32 0, i32 1
  %t50 = load ptr, ptr %t49, align 8
  %t51 = load ptr, ptr %sc.addr.0, align 8
  %t52 = getelementptr inbounds %Scope, ptr %t51, i32 0, i32 2
  %t53 = load i32, ptr %t52, align 4
  %t54 = sext i32 %t53 to i64
  %t55 = getelementptr inbounds %Sym, ptr %t50, i64 %t54
  store ptr %t55, ptr %sym.addr.47, align 8
  %t56 = load ptr, ptr %sym.addr.47, align 8
  %t57 = load ptr, ptr %name.addr, align 8
  %t58 = getelementptr inbounds %Sym, ptr %t56, i32 0, i32 0
  store ptr %t57, ptr %t58, align 8
  %t59 = load ptr, ptr %sym.addr.47, align 8
  %t60 = load ptr, ptr %type.addr, align 8
  %t61 = getelementptr inbounds %Sym, ptr %t59, i32 0, i32 1
  store ptr %t60, ptr %t61, align 8
  %t62 = load ptr, ptr %sym.addr.47, align 8
  %t63 = load ptr, ptr %ir-name.addr, align 8
  %t64 = getelementptr inbounds %Sym, ptr %t62, i32 0, i32 2
  store ptr %t63, ptr %t64, align 8
  %t65 = load ptr, ptr %sym.addr.47, align 8
  %t66 = load i32, ptr %is-local.addr, align 4
  %t67 = getelementptr inbounds %Sym, ptr %t65, i32 0, i32 3
  store i32 %t66, ptr %t67, align 4
  %t68 = load ptr, ptr %sc.addr.0, align 8
  %t69 = load ptr, ptr %sc.addr.0, align 8
  %t70 = getelementptr inbounds %Scope, ptr %t69, i32 0, i32 2
  %t71 = load i32, ptr %t70, align 4
  %t72 = add nsw i32 %t71, 1
  %t73 = getelementptr inbounds %Scope, ptr %t68, i32 0, i32 2
  store i32 %t72, ptr %t73, align 4
  %t74 = load ptr, ptr %sym.addr.47, align 8
  ret ptr %t74
}

define ptr @scope-lookup(ptr %s.arg, ptr %name.arg) {
entry:
  %s.addr = alloca ptr, align 8
  store ptr %s.arg, ptr %s.addr, align 8
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %cur.addr.0 = alloca ptr, align 8
  %sc.addr.4 = alloca ptr, align 8
  %i.addr.6 = alloca i32, align 4
  %sym.addr.13 = alloca ptr, align 8
  %t1 = load ptr, ptr %s.addr, align 8
  store ptr %t1, ptr %cur.addr.0, align 8
  br label %while.cond0
while.cond0:
  %t2 = load ptr, ptr %cur.addr.0, align 8
  %t3 = icmp ne ptr %t2, null
  br i1 %t3, label %while.body0, label %while.end0
while.body0:
  %t5 = load ptr, ptr %cur.addr.0, align 8
  store ptr %t5, ptr %sc.addr.4, align 8
  %t7 = load ptr, ptr %sc.addr.4, align 8
  %t8 = getelementptr inbounds %Scope, ptr %t7, i32 0, i32 2
  %t9 = load i32, ptr %t8, align 4
  %t10 = sub nsw i32 %t9, 1
  store i32 %t10, ptr %i.addr.6, align 4
  br label %while.cond1
while.cond1:
  %t11 = load i32, ptr %i.addr.6, align 4
  %t12 = icmp sge i32 %t11, 0
  br i1 %t12, label %while.body1, label %while.end1
while.body1:
  %t14 = load ptr, ptr %sc.addr.4, align 8
  %t15 = getelementptr inbounds %Scope, ptr %t14, i32 0, i32 1
  %t16 = load ptr, ptr %t15, align 8
  %t17 = load i32, ptr %i.addr.6, align 4
  %t18 = sext i32 %t17 to i64
  %t19 = getelementptr inbounds %Sym, ptr %t16, i64 %t18
  store ptr %t19, ptr %sym.addr.13, align 8
  %t20 = load ptr, ptr %sym.addr.13, align 8
  %t21 = getelementptr inbounds %Sym, ptr %t20, i32 0, i32 0
  %t22 = load ptr, ptr %t21, align 8
  %t23 = load ptr, ptr %name.addr, align 8
  %t24 = call i32 @strcmp(ptr %t22, ptr %t23)
  %t25 = icmp eq i32 %t24, 0
  br i1 %t25, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t26 = load ptr, ptr %sym.addr.13, align 8
  ret ptr %t26
cond.end2:
  %t27 = load i32, ptr %i.addr.6, align 4
  %t28 = sub nsw i32 %t27, 1
  store i32 %t28, ptr %i.addr.6, align 4
  br label %while.cond1
while.end1:
  %t29 = load ptr, ptr %sc.addr.4, align 8
  %t30 = getelementptr inbounds %Scope, ptr %t29, i32 0, i32 0
  %t31 = load ptr, ptr %t30, align 8
  store ptr %t31, ptr %cur.addr.0, align 8
  br label %while.cond0
while.end0:
  ret ptr null
}

define i32 @intern-string(ptr %bytes.arg, i32 %len.arg) {
entry:
  %bytes.addr = alloca ptr, align 8
  store ptr %bytes.arg, ptr %bytes.addr, align 8
  %len.addr = alloca i32, align 4
  store i32 %len.arg, ptr %len.addr, align 4
  %id.addr.0 = alloca i32, align 4
  %nc.addr.5 = alloca i32, align 4
  %ns.addr.10 = alloca ptr, align 8
  %sl.addr.33 = alloca ptr, align 8
  %t1 = load i32, ptr @g-strs-len, align 4
  store i32 %t1, ptr %id.addr.0, align 4
  %t2 = load i32, ptr @g-strs-len, align 4
  %t3 = load i32, ptr @g-strs-cap, align 4
  %t4 = icmp eq i32 %t2, %t3
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  store i32 8, ptr %nc.addr.5, align 4
  %t6 = load i32, ptr @g-strs-cap, align 4
  %t7 = icmp ne i32 %t6, 0
  br i1 %t7, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t8 = load i32, ptr @g-strs-cap, align 4
  %t9 = mul nsw i32 %t8, 2
  store i32 %t9, ptr %nc.addr.5, align 4
  br label %cond.end1
cond.end1:
  %t11 = load i32, ptr %nc.addr.5, align 4
  %t12 = call i64 @i64(i32 %t11)
  %t13 = getelementptr %StrLit, ptr null, i32 1
  %t14 = ptrtoint ptr %t13 to i64
  %t15 = mul nsw i64 %t12, %t14
  %t16 = call ptr @malloc(i64 %t15)
  store ptr %t16, ptr %ns.addr.10, align 8
  %t17 = load ptr, ptr %ns.addr.10, align 8
  %t18 = icmp eq ptr %t17, null
  br i1 %t18, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t19 = getelementptr inbounds [7 x i8], ptr @.str.52, i64 0, i64 0
  call void @perror(ptr %t19)
  call void @exit(i32 1)
  br label %cond.end2
cond.end2:
  %t20 = load ptr, ptr @g-strs, align 8
  %t21 = icmp ne ptr %t20, null
  br i1 %t21, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t22 = load ptr, ptr %ns.addr.10, align 8
  %t23 = load ptr, ptr @g-strs, align 8
  %t24 = load i32, ptr @g-strs-len, align 4
  %t25 = call i64 @i64(i32 %t24)
  %t26 = getelementptr %StrLit, ptr null, i32 1
  %t27 = ptrtoint ptr %t26 to i64
  %t28 = mul nsw i64 %t25, %t27
  %t29 = call ptr @memcpy(ptr %t22, ptr %t23, i64 %t28)
  %t30 = load ptr, ptr @g-strs, align 8
  call void @free(ptr %t30)
  br label %cond.end3
cond.end3:
  %t31 = load ptr, ptr %ns.addr.10, align 8
  store ptr %t31, ptr @g-strs, align 8
  %t32 = load i32, ptr %nc.addr.5, align 4
  store i32 %t32, ptr @g-strs-cap, align 4
  br label %cond.end0
cond.end0:
  %t34 = load ptr, ptr @g-strs, align 8
  %t35 = load i32, ptr @g-strs-len, align 4
  %t36 = sext i32 %t35 to i64
  %t37 = getelementptr inbounds %StrLit, ptr %t34, i64 %t36
  store ptr %t37, ptr %sl.addr.33, align 8
  %t38 = load ptr, ptr %sl.addr.33, align 8
  %t39 = load ptr, ptr %bytes.addr, align 8
  %t40 = load i32, ptr %len.addr, align 4
  %t41 = call i64 @i64(i32 %t40)
  %t42 = call ptr @arena-strndup(ptr %t39, i64 %t41)
  %t43 = getelementptr inbounds %StrLit, ptr %t38, i32 0, i32 0
  store ptr %t42, ptr %t43, align 8
  %t44 = load ptr, ptr %sl.addr.33, align 8
  %t45 = load i32, ptr %len.addr, align 4
  %t46 = getelementptr inbounds %StrLit, ptr %t44, i32 0, i32 1
  store i32 %t45, ptr %t46, align 4
  %t47 = load ptr, ptr %sl.addr.33, align 8
  %t48 = load i32, ptr %id.addr.0, align 4
  %t49 = getelementptr inbounds %StrLit, ptr %t47, i32 0, i32 2
  store i32 %t48, ptr %t49, align 4
  %t50 = load i32, ptr @g-strs-len, align 4
  %t51 = add nsw i32 %t50, 1
  store i32 %t51, ptr @g-strs-len, align 4
  %t52 = load i32, ptr %id.addr.0, align 4
  ret i32 %t52
}

define ptr @new-tmp() {
entry:
  %r.addr.0 = alloca ptr, align 8
  %t1 = getelementptr inbounds [6 x i8], ptr @.str.53, i64 0, i64 0
  %t2 = load i32, ptr @g-tmp, align 4
  %t3 = call ptr @fmt-i32(ptr %t1, i32 %t2)
  store ptr %t3, ptr %r.addr.0, align 8
  %t4 = load i32, ptr @g-tmp, align 4
  %t5 = add nsw i32 %t4, 1
  store i32 %t5, ptr @g-tmp, align 4
  %t6 = load ptr, ptr %r.addr.0, align 8
  ret ptr %t6
}

define i32 @new-label-id() {
entry:
  %r.addr.0 = alloca i32, align 4
  %t1 = load i32, ptr @g-label, align 4
  store i32 %t1, ptr %r.addr.0, align 4
  %t2 = load i32, ptr @g-label, align 4
  %t3 = add nsw i32 %t2, 1
  store i32 %t3, ptr @g-label, align 4
  %t4 = load i32, ptr %r.addr.0, align 4
  ret i32 %t4
}

define void @reset-function-state() {
entry:
  store i32 0, ptr @g-tmp, align 4
  store i32 0, ptr @g-label, align 4
  store i32 0, ptr @g-block-term, align 4
  %t0 = call ptr @open_memstream(ptr @g-entry-bufp, ptr @g-entry-sizep)
  store ptr %t0, ptr @g-entry-stream, align 8
  %t1 = call ptr @open_memstream(ptr @g-body-bufp, ptr @g-body-sizep)
  store ptr %t1, ptr @g-body-stream, align 8
  ret void
}

define ptr @emit-node(ptr %n.arg, ptr %scope.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %nn.addr.0 = alloca ptr, align 8
  %t1 = load ptr, ptr %n.addr, align 8
  store ptr %t1, ptr %nn.addr.0, align 8
  %t2 = load ptr, ptr %nn.addr.0, align 8
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 0
  %t4 = load i32, ptr %t3, align 4
  %t5 = icmp eq i32 %t4, 0
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t6 = load ptr, ptr %n.addr, align 8
  %t7 = call ptr @emit-int(ptr %t6)
  ret ptr %t7
cond.end0:
  %t8 = load ptr, ptr %nn.addr.0, align 8
  %t9 = getelementptr inbounds %Node, ptr %t8, i32 0, i32 0
  %t10 = load i32, ptr %t9, align 4
  %t11 = icmp eq i32 %t10, 1
  br i1 %t11, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t12 = load ptr, ptr %n.addr, align 8
  %t13 = call ptr @emit-string(ptr %t12)
  ret ptr %t13
cond.end1:
  %t14 = load ptr, ptr %nn.addr.0, align 8
  %t15 = getelementptr inbounds %Node, ptr %t14, i32 0, i32 0
  %t16 = load i32, ptr %t15, align 4
  %t17 = icmp eq i32 %t16, 2
  br i1 %t17, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t18 = load ptr, ptr %n.addr, align 8
  %t19 = load ptr, ptr %scope.addr, align 8
  %t20 = call ptr @emit-symbol-ref(ptr %t18, ptr %t19)
  ret ptr %t20
cond.end2:
  %t21 = load ptr, ptr %nn.addr.0, align 8
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 0
  %t23 = load i32, ptr %t22, align 4
  %t24 = icmp eq i32 %t23, 3
  br i1 %t24, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t25 = load ptr, ptr %n.addr, align 8
  %t26 = load ptr, ptr %scope.addr, align 8
  %t27 = call ptr @emit-list(ptr %t25, ptr %t26)
  ret ptr %t27
cond.end3:
  %t28 = load ptr, ptr @ty-void, align 8
  %t29 = call ptr @alloc-val(ptr %t28, ptr null)
  ret ptr %t29
}

define ptr @emit-int(ptr %n.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %t0 = load ptr, ptr @ty-i32, align 8
  %t1 = getelementptr inbounds [4 x i8], ptr @.str.54, i64 0, i64 0
  %t2 = load ptr, ptr %n.addr, align 8
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 2
  %t4 = load i64, ptr %t3, align 8
  %t5 = call ptr @fmt-i64(ptr %t1, i64 %t4)
  %t6 = call ptr @alloc-val(ptr %t0, ptr %t5)
  ret ptr %t6
}

define ptr @emit-string(ptr %n.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %nn.addr.0 = alloca ptr, align 8
  %id.addr.2 = alloca i32, align 4
  %ir-len.addr.12 = alloca i32, align 4
  %tmp.addr.20 = alloca ptr, align 8
  %t1 = load ptr, ptr %n.addr, align 8
  store ptr %t1, ptr %nn.addr.0, align 8
  %t3 = load ptr, ptr %nn.addr.0, align 8
  %t4 = getelementptr inbounds %Node, ptr %t3, i32 0, i32 3
  %t5 = load ptr, ptr %t4, align 8
  %t6 = load ptr, ptr %nn.addr.0, align 8
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 3
  %t8 = load ptr, ptr %t7, align 8
  %t9 = call i64 @strlen(ptr %t8)
  %t10 = trunc i64 %t9 to i32
  %t11 = call i32 @intern-string(ptr %t5, i32 %t10)
  store i32 %t11, ptr %id.addr.2, align 4
  %t13 = load ptr, ptr @g-strs, align 8
  %t14 = load i32, ptr %id.addr.2, align 4
  %t15 = sext i32 %t14 to i64
  %t16 = getelementptr inbounds %StrLit, ptr %t13, i64 %t15
  %t17 = getelementptr inbounds %StrLit, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = add nsw i32 %t18, 1
  store i32 %t19, ptr %ir-len.addr.12, align 4
  %t21 = call ptr @new-tmp()
  store ptr %t21, ptr %tmp.addr.20, align 8
  %t22 = load ptr, ptr @g-body-stream, align 8
  %t23 = getelementptr inbounds [69 x i8], ptr @.str.55, i64 0, i64 0
  %t24 = load ptr, ptr %tmp.addr.20, align 8
  %t25 = load i32, ptr %ir-len.addr.12, align 4
  %t26 = load i32, ptr %id.addr.2, align 4
  %t27 = call i32 (ptr, ptr, ...) @fprintf(ptr %t22, ptr %t23, ptr %t24, i32 %t25, i32 %t26)
  %t28 = load ptr, ptr @ty-ptr, align 8
  %t29 = load ptr, ptr %tmp.addr.20, align 8
  %t30 = call ptr @alloc-val(ptr %t28, ptr %t29)
  ret ptr %t30
}

define ptr @emit-quote-tree(ptr %n.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %nn.addr.3 = alloca ptr, align 8
  %id.addr.9 = alloca i32, align 4
  %or.val3 = alloca i1, align 1
  %k.addr.36 = alloca i32, align 4
  %sid.addr.41 = alloca i32, align 4
  %ir-len.addr.51 = alloca i32, align 4
  %id.addr.59 = alloca i32, align 4
  %car-ref.addr.77 = alloca ptr, align 8
  %cdr-ref.addr.82 = alloca ptr, align 8
  %id.addr.87 = alloca i32, align 4
  %t0 = load ptr, ptr %n.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t2 = getelementptr inbounds [5 x i8], ptr @.str.56, i64 0, i64 0
  ret ptr %t2
cond.end0:
  %t4 = load ptr, ptr %n.addr, align 8
  store ptr %t4, ptr %nn.addr.3, align 8
  %t5 = load ptr, ptr %nn.addr.3, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 0
  %t7 = load i32, ptr %t6, align 4
  %t8 = icmp eq i32 %t7, 0
  br i1 %t8, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t10 = load i32, ptr @g-quote-id, align 4
  store i32 %t10, ptr %id.addr.9, align 4
  %t11 = load i32, ptr @g-quote-id, align 4
  %t12 = add nsw i32 %t11, 1
  store i32 %t12, ptr @g-quote-id, align 4
  %t13 = load ptr, ptr @g-decl-out, align 8
  %t14 = getelementptr inbounds [138 x i8], ptr @.str.57, i64 0, i64 0
  %t15 = load i32, ptr %id.addr.9, align 4
  %t16 = load ptr, ptr %nn.addr.3, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = load ptr, ptr %nn.addr.3, align 8
  %t20 = getelementptr inbounds %Node, ptr %t19, i32 0, i32 2
  %t21 = load i64, ptr %t20, align 8
  %t22 = call i32 (ptr, ptr, ...) @fprintf(ptr %t13, ptr %t14, i32 %t15, i32 %t18, i64 %t21)
  %t23 = getelementptr inbounds [7 x i8], ptr @.str.58, i64 0, i64 0
  %t24 = load i32, ptr %id.addr.9, align 4
  %t25 = sext i32 %t24 to i64
  %t26 = call ptr @fmt-i64(ptr %t23, i64 %t25)
  ret ptr %t26
cond.end1:
  %t27 = load ptr, ptr %nn.addr.3, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 0
  %t29 = load i32, ptr %t28, align 4
  %t30 = icmp eq i32 %t29, 1
  store i1 %t30, ptr %or.val3, align 1
  br i1 %t30, label %or.end3, label %or.rhs3
or.rhs3:
  %t31 = load ptr, ptr %nn.addr.3, align 8
  %t32 = getelementptr inbounds %Node, ptr %t31, i32 0, i32 0
  %t33 = load i32, ptr %t32, align 4
  %t34 = icmp eq i32 %t33, 2
  store i1 %t34, ptr %or.val3, align 1
  br label %or.end3
or.end3:
  %t35 = load i1, ptr %or.val3, align 1
  br i1 %t35, label %cond.then2.0, label %cond.end2
cond.then2.0:
  store i32 2, ptr %k.addr.36, align 4
  %t37 = load ptr, ptr %nn.addr.3, align 8
  %t38 = getelementptr inbounds %Node, ptr %t37, i32 0, i32 0
  %t39 = load i32, ptr %t38, align 4
  %t40 = icmp eq i32 %t39, 1
  br i1 %t40, label %cond.then4.0, label %cond.end4
cond.then4.0:
  store i32 1, ptr %k.addr.36, align 4
  br label %cond.end4
cond.end4:
  %t42 = load ptr, ptr %nn.addr.3, align 8
  %t43 = getelementptr inbounds %Node, ptr %t42, i32 0, i32 3
  %t44 = load ptr, ptr %t43, align 8
  %t45 = load ptr, ptr %nn.addr.3, align 8
  %t46 = getelementptr inbounds %Node, ptr %t45, i32 0, i32 3
  %t47 = load ptr, ptr %t46, align 8
  %t48 = call i64 @strlen(ptr %t47)
  %t49 = trunc i64 %t48 to i32
  %t50 = call i32 @intern-string(ptr %t44, i32 %t49)
  store i32 %t50, ptr %sid.addr.41, align 4
  %t52 = load ptr, ptr @g-strs, align 8
  %t53 = load i32, ptr %sid.addr.41, align 4
  %t54 = sext i32 %t53 to i64
  %t55 = getelementptr inbounds %StrLit, ptr %t52, i64 %t54
  %t56 = getelementptr inbounds %StrLit, ptr %t55, i32 0, i32 1
  %t57 = load i32, ptr %t56, align 4
  %t58 = add nsw i32 %t57, 1
  store i32 %t58, ptr %ir-len.addr.51, align 4
  %t60 = load i32, ptr @g-quote-id, align 4
  store i32 %t60, ptr %id.addr.59, align 4
  %t61 = load i32, ptr @g-quote-id, align 4
  %t62 = add nsw i32 %t61, 1
  store i32 %t62, ptr @g-quote-id, align 4
  %t63 = load ptr, ptr @g-decl-out, align 8
  %t64 = getelementptr inbounds [195 x i8], ptr @.str.59, i64 0, i64 0
  %t65 = load i32, ptr %id.addr.59, align 4
  %t66 = load i32, ptr %k.addr.36, align 4
  %t67 = load ptr, ptr %nn.addr.3, align 8
  %t68 = getelementptr inbounds %Node, ptr %t67, i32 0, i32 1
  %t69 = load i32, ptr %t68, align 4
  %t70 = load i32, ptr %ir-len.addr.51, align 4
  %t71 = load i32, ptr %sid.addr.41, align 4
  %t72 = call i32 (ptr, ptr, ...) @fprintf(ptr %t63, ptr %t64, i32 %t65, i32 %t66, i32 %t69, i32 %t70, i32 %t71)
  %t73 = getelementptr inbounds [7 x i8], ptr @.str.60, i64 0, i64 0
  %t74 = load i32, ptr %id.addr.59, align 4
  %t75 = sext i32 %t74 to i64
  %t76 = call ptr @fmt-i64(ptr %t73, i64 %t75)
  ret ptr %t76
cond.end2:
  %t78 = load ptr, ptr %nn.addr.3, align 8
  %t79 = getelementptr inbounds %Node, ptr %t78, i32 0, i32 4
  %t80 = load ptr, ptr %t79, align 8
  %t81 = call ptr @emit-quote-tree(ptr %t80)
  store ptr %t81, ptr %car-ref.addr.77, align 8
  %t83 = load ptr, ptr %nn.addr.3, align 8
  %t84 = getelementptr inbounds %Node, ptr %t83, i32 0, i32 5
  %t85 = load ptr, ptr %t84, align 8
  %t86 = call ptr @emit-quote-tree(ptr %t85)
  store ptr %t86, ptr %cdr-ref.addr.82, align 8
  %t88 = load i32, ptr @g-quote-id, align 4
  store i32 %t88, ptr %id.addr.87, align 4
  %t89 = load i32, ptr @g-quote-id, align 4
  %t90 = add nsw i32 %t89, 1
  store i32 %t90, ptr @g-quote-id, align 4
  %t91 = load ptr, ptr @g-decl-out, align 8
  %t92 = getelementptr inbounds [132 x i8], ptr @.str.61, i64 0, i64 0
  %t93 = load i32, ptr %id.addr.87, align 4
  %t94 = load ptr, ptr %nn.addr.3, align 8
  %t95 = getelementptr inbounds %Node, ptr %t94, i32 0, i32 1
  %t96 = load i32, ptr %t95, align 4
  %t97 = load ptr, ptr %car-ref.addr.77, align 8
  %t98 = load ptr, ptr %cdr-ref.addr.82, align 8
  %t99 = call i32 (ptr, ptr, ...) @fprintf(ptr %t91, ptr %t92, i32 %t93, i32 %t96, ptr %t97, ptr %t98)
  %t100 = getelementptr inbounds [7 x i8], ptr @.str.62, i64 0, i64 0
  %t101 = load i32, ptr %id.addr.87, align 4
  %t102 = sext i32 %t101 to i64
  %t103 = call ptr @fmt-i64(ptr %t100, i64 %t102)
  ret ptr %t103
}

define ptr @emit-quote(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %ref.addr.9 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %call.addr, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [21 x i8], ptr @.str.63, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %call.addr, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = call ptr @emit-quote-tree(ptr %t11)
  store ptr %t12, ptr %ref.addr.9, align 8
  %t13 = load ptr, ptr @ty-ptr, align 8
  %t14 = load ptr, ptr %ref.addr.9, align 8
  %t15 = call ptr @alloc-val(ptr %t13, ptr %t14)
  ret ptr %t15
}

define i32 @qq-is-tagged(ptr %n.arg, ptr %tag.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %tag.addr = alloca ptr, align 8
  store ptr %tag.arg, ptr %tag.addr, align 8
  %nn.addr.2 = alloca ptr, align 8
  %h.addr.11 = alloca ptr, align 8
  %t0 = load ptr, ptr %n.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret i32 0
cond.end0:
  %t3 = load ptr, ptr %n.addr, align 8
  store ptr %t3, ptr %nn.addr.2, align 8
  %t4 = load ptr, ptr %nn.addr.2, align 8
  %t5 = getelementptr inbounds %Node, ptr %t4, i32 0, i32 0
  %t6 = load i32, ptr %t5, align 4
  %t7 = icmp ne i32 %t6, 3
  br i1 %t7, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret i32 0
cond.end1:
  %t8 = load ptr, ptr %n.addr, align 8
  %t9 = call i32 @node-len(ptr %t8)
  %t10 = icmp ne i32 %t9, 2
  br i1 %t10, label %cond.then2.0, label %cond.end2
cond.then2.0:
  ret i32 0
cond.end2:
  %t12 = load ptr, ptr %nn.addr.2, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 4
  %t14 = load ptr, ptr %t13, align 8
  store ptr %t14, ptr %h.addr.11, align 8
  %t15 = load ptr, ptr %h.addr.11, align 8
  %t16 = icmp eq ptr %t15, null
  br i1 %t16, label %cond.then3.0, label %cond.end3
cond.then3.0:
  ret i32 0
cond.end3:
  %t17 = load ptr, ptr %h.addr.11, align 8
  %t18 = getelementptr inbounds %Node, ptr %t17, i32 0, i32 0
  %t19 = load i32, ptr %t18, align 4
  %t20 = icmp ne i32 %t19, 2
  br i1 %t20, label %cond.then4.0, label %cond.end4
cond.then4.0:
  ret i32 0
cond.end4:
  %t21 = load ptr, ptr %h.addr.11, align 8
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 3
  %t23 = load ptr, ptr %t22, align 8
  %t24 = load ptr, ptr %tag.addr, align 8
  %t25 = call i32 @strcmp(ptr %t23, ptr %t24)
  %t26 = icmp eq i32 %t25, 0
  br i1 %t26, label %cond.then5.0, label %cond.end5
cond.then5.0:
  ret i32 1
cond.end5:
  ret i32 0
}

define ptr @emit-qq-list(ptr %list.arg, ptr %scope.arg) {
entry:
  %list.addr = alloca ptr, align 8
  store ptr %list.arg, ptr %list.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %lc.addr.5 = alloca ptr, align 8
  %elem.addr.7 = alloca ptr, align 8
  %inner.addr.15 = alloca ptr, align 8
  %a.addr.18 = alloca ptr, align 8
  %rest.addr.22 = alloca ptr, align 8
  %tmp.addr.28 = alloca ptr, align 8
  %head.addr.43 = alloca ptr, align 8
  %tail.addr.47 = alloca ptr, align 8
  %tmp.addr.53 = alloca ptr, align 8
  %t0 = load ptr, ptr %list.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t2 = load ptr, ptr @ty-ptr, align 8
  %t3 = getelementptr inbounds [5 x i8], ptr @.str.64, i64 0, i64 0
  %t4 = call ptr @alloc-val(ptr %t2, ptr %t3)
  ret ptr %t4
cond.end0:
  store i32 1, ptr @g-qq-used, align 4
  %t6 = load ptr, ptr %list.addr, align 8
  store ptr %t6, ptr %lc.addr.5, align 8
  %t8 = load ptr, ptr %lc.addr.5, align 8
  %t9 = getelementptr inbounds %Node, ptr %t8, i32 0, i32 4
  %t10 = load ptr, ptr %t9, align 8
  store ptr %t10, ptr %elem.addr.7, align 8
  %t11 = load ptr, ptr %elem.addr.7, align 8
  %t12 = getelementptr inbounds [15 x i8], ptr @.str.65, i64 0, i64 0
  %t13 = call i32 @qq-is-tagged(ptr %t11, ptr %t12)
  %t14 = icmp ne i32 %t13, 0
  br i1 %t14, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %elem.addr.7, align 8
  %t17 = call ptr @node-at(ptr %t16, i32 1)
  store ptr %t17, ptr %inner.addr.15, align 8
  %t19 = load ptr, ptr %inner.addr.15, align 8
  %t20 = load ptr, ptr %scope.addr, align 8
  %t21 = call ptr @emit-node(ptr %t19, ptr %t20)
  store ptr %t21, ptr %a.addr.18, align 8
  %t23 = load ptr, ptr %lc.addr.5, align 8
  %t24 = getelementptr inbounds %Node, ptr %t23, i32 0, i32 5
  %t25 = load ptr, ptr %t24, align 8
  %t26 = load ptr, ptr %scope.addr, align 8
  %t27 = call ptr @emit-qq-list(ptr %t25, ptr %t26)
  store ptr %t27, ptr %rest.addr.22, align 8
  %t29 = call ptr @new-tmp()
  store ptr %t29, ptr %tmp.addr.28, align 8
  %t30 = load ptr, ptr @g-body-stream, align 8
  %t31 = getelementptr inbounds [43 x i8], ptr @.str.66, i64 0, i64 0
  %t32 = load ptr, ptr %tmp.addr.28, align 8
  %t33 = load ptr, ptr %a.addr.18, align 8
  %t34 = getelementptr inbounds %Val, ptr %t33, i32 0, i32 1
  %t35 = load ptr, ptr %t34, align 8
  %t36 = load ptr, ptr %rest.addr.22, align 8
  %t37 = getelementptr inbounds %Val, ptr %t36, i32 0, i32 1
  %t38 = load ptr, ptr %t37, align 8
  %t39 = call i32 (ptr, ptr, ...) @fprintf(ptr %t30, ptr %t31, ptr %t32, ptr %t35, ptr %t38)
  %t40 = load ptr, ptr @ty-ptr, align 8
  %t41 = load ptr, ptr %tmp.addr.28, align 8
  %t42 = call ptr @alloc-val(ptr %t40, ptr %t41)
  ret ptr %t42
cond.end1:
  %t44 = load ptr, ptr %elem.addr.7, align 8
  %t45 = load ptr, ptr %scope.addr, align 8
  %t46 = call ptr @emit-qq-form(ptr %t44, ptr %t45)
  store ptr %t46, ptr %head.addr.43, align 8
  %t48 = load ptr, ptr %lc.addr.5, align 8
  %t49 = getelementptr inbounds %Node, ptr %t48, i32 0, i32 5
  %t50 = load ptr, ptr %t49, align 8
  %t51 = load ptr, ptr %scope.addr, align 8
  %t52 = call ptr @emit-qq-list(ptr %t50, ptr %t51)
  store ptr %t52, ptr %tail.addr.47, align 8
  %t54 = call ptr @new-tmp()
  store ptr %t54, ptr %tmp.addr.53, align 8
  %t55 = load ptr, ptr @g-body-stream, align 8
  %t56 = getelementptr inbounds [41 x i8], ptr @.str.67, i64 0, i64 0
  %t57 = load ptr, ptr %tmp.addr.53, align 8
  %t58 = load ptr, ptr %head.addr.43, align 8
  %t59 = getelementptr inbounds %Val, ptr %t58, i32 0, i32 1
  %t60 = load ptr, ptr %t59, align 8
  %t61 = load ptr, ptr %tail.addr.47, align 8
  %t62 = getelementptr inbounds %Val, ptr %t61, i32 0, i32 1
  %t63 = load ptr, ptr %t62, align 8
  %t64 = call i32 (ptr, ptr, ...) @fprintf(ptr %t55, ptr %t56, ptr %t57, ptr %t60, ptr %t63)
  %t65 = load ptr, ptr @ty-ptr, align 8
  %t66 = load ptr, ptr %tmp.addr.53, align 8
  %t67 = call ptr @alloc-val(ptr %t65, ptr %t66)
  ret ptr %t67
}

define ptr @emit-qq-form(ptr %form.arg, ptr %scope.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %fn.addr.5 = alloca ptr, align 8
  %ref.addr.11 = alloca ptr, align 8
  %t0 = load ptr, ptr %form.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t2 = load ptr, ptr @ty-ptr, align 8
  %t3 = getelementptr inbounds [5 x i8], ptr @.str.68, i64 0, i64 0
  %t4 = call ptr @alloc-val(ptr %t2, ptr %t3)
  ret ptr %t4
cond.end0:
  %t6 = load ptr, ptr %form.addr, align 8
  store ptr %t6, ptr %fn.addr.5, align 8
  %t7 = load ptr, ptr %fn.addr.5, align 8
  %t8 = getelementptr inbounds %Node, ptr %t7, i32 0, i32 0
  %t9 = load i32, ptr %t8, align 4
  %t10 = icmp ne i32 %t9, 3
  br i1 %t10, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t12 = load ptr, ptr %form.addr, align 8
  %t13 = call ptr @emit-quote-tree(ptr %t12)
  store ptr %t13, ptr %ref.addr.11, align 8
  %t14 = load ptr, ptr @ty-ptr, align 8
  %t15 = load ptr, ptr %ref.addr.11, align 8
  %t16 = call ptr @alloc-val(ptr %t14, ptr %t15)
  ret ptr %t16
cond.end1:
  %t17 = load ptr, ptr %form.addr, align 8
  %t18 = getelementptr inbounds [8 x i8], ptr @.str.69, i64 0, i64 0
  %t19 = call i32 @qq-is-tagged(ptr %t17, ptr %t18)
  %t20 = icmp ne i32 %t19, 0
  br i1 %t20, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t21 = load ptr, ptr %form.addr, align 8
  %t22 = call ptr @node-at(ptr %t21, i32 1)
  %t23 = load ptr, ptr %scope.addr, align 8
  %t24 = call ptr @emit-node(ptr %t22, ptr %t23)
  ret ptr %t24
cond.end2:
  %t25 = load ptr, ptr %form.addr, align 8
  %t26 = getelementptr inbounds [15 x i8], ptr @.str.70, i64 0, i64 0
  %t27 = call i32 @qq-is-tagged(ptr %t25, ptr %t26)
  %t28 = icmp ne i32 %t27, 0
  br i1 %t28, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t29 = load ptr, ptr %fn.addr.5, align 8
  %t30 = getelementptr inbounds %Node, ptr %t29, i32 0, i32 1
  %t31 = load i32, ptr %t30, align 4
  %t32 = getelementptr inbounds [28 x i8], ptr @.str.71, i64 0, i64 0
  call void @die-at(i32 %t31, ptr %t32)
  br label %cond.end3
cond.end3:
  %t33 = load ptr, ptr %form.addr, align 8
  %t34 = load ptr, ptr %scope.addr, align 8
  %t35 = call ptr @emit-qq-list(ptr %t33, ptr %t34)
  ret ptr %t35
}

define ptr @emit-quasiquote(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %call.addr, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [26 x i8], ptr @.str.72, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t9 = load ptr, ptr %call.addr, align 8
  %t10 = call ptr @node-at(ptr %t9, i32 1)
  %t11 = load ptr, ptr %scope.addr, align 8
  %t12 = call ptr @emit-qq-form(ptr %t10, ptr %t11)
  ret ptr %t12
}

define ptr @emit-symbol-ref(ptr %n.arg, ptr %scope.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %nn.addr.0 = alloca ptr, align 8
  %lookup-name.addr.29 = alloca ptr, align 8
  %ignored-type.addr.30 = alloca ptr, align 8
  %sym.addr.34 = alloca ptr, align 8
  %tmp.addr.71 = alloca ptr, align 8
  %t1 = load ptr, ptr %n.addr, align 8
  store ptr %t1, ptr %nn.addr.0, align 8
  %t2 = load ptr, ptr %nn.addr.0, align 8
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 3
  %t4 = load ptr, ptr %t3, align 8
  %t5 = getelementptr inbounds [5 x i8], ptr @.str.73, i64 0, i64 0
  %t6 = call i32 @strcmp(ptr %t4, ptr %t5)
  %t7 = icmp eq i32 %t6, 0
  br i1 %t7, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t8 = load ptr, ptr @ty-ptr, align 8
  %t9 = getelementptr inbounds [5 x i8], ptr @.str.74, i64 0, i64 0
  %t10 = call ptr @alloc-val(ptr %t8, ptr %t9)
  ret ptr %t10
cond.end0:
  %t11 = load ptr, ptr %nn.addr.0, align 8
  %t12 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 3
  %t13 = load ptr, ptr %t12, align 8
  %t14 = getelementptr inbounds [5 x i8], ptr @.str.75, i64 0, i64 0
  %t15 = call i32 @strcmp(ptr %t13, ptr %t14)
  %t16 = icmp eq i32 %t15, 0
  br i1 %t16, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t17 = load ptr, ptr @ty-i1, align 8
  %t18 = getelementptr inbounds [2 x i8], ptr @.str.76, i64 0, i64 0
  %t19 = call ptr @alloc-val(ptr %t17, ptr %t18)
  ret ptr %t19
cond.end1:
  %t20 = load ptr, ptr %nn.addr.0, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 3
  %t22 = load ptr, ptr %t21, align 8
  %t23 = getelementptr inbounds [6 x i8], ptr @.str.77, i64 0, i64 0
  %t24 = call i32 @strcmp(ptr %t22, ptr %t23)
  %t25 = icmp eq i32 %t24, 0
  br i1 %t25, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t26 = load ptr, ptr @ty-i1, align 8
  %t27 = getelementptr inbounds [2 x i8], ptr @.str.78, i64 0, i64 0
  %t28 = call ptr @alloc-val(ptr %t26, ptr %t27)
  ret ptr %t28
cond.end2:
  store ptr null, ptr %lookup-name.addr.29, align 8
  store ptr null, ptr %ignored-type.addr.30, align 8
  %t31 = load ptr, ptr %nn.addr.0, align 8
  %t32 = getelementptr inbounds %Node, ptr %t31, i32 0, i32 3
  %t33 = load ptr, ptr %t32, align 8
  call void @split-typed(ptr %t33, ptr %lookup-name.addr.29, ptr %ignored-type.addr.30)
  %t35 = load ptr, ptr %scope.addr, align 8
  %t36 = load ptr, ptr %lookup-name.addr.29, align 8
  %t37 = call ptr @scope-lookup(ptr %t35, ptr %t36)
  store ptr %t37, ptr %sym.addr.34, align 8
  %t38 = load ptr, ptr %sym.addr.34, align 8
  %t39 = icmp eq ptr %t38, null
  br i1 %t39, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t40 = load ptr, ptr %nn.addr.0, align 8
  %t41 = getelementptr inbounds %Node, ptr %t40, i32 0, i32 1
  %t42 = load i32, ptr %t41, align 4
  %t43 = getelementptr inbounds [14 x i8], ptr @.str.79, i64 0, i64 0
  %t44 = load ptr, ptr %nn.addr.0, align 8
  %t45 = getelementptr inbounds %Node, ptr %t44, i32 0, i32 3
  %t46 = load ptr, ptr %t45, align 8
  %t47 = call ptr @fmt-s(ptr %t43, ptr %t46)
  call void @die-at(i32 %t42, ptr %t47)
  br label %cond.end3
cond.end3:
  %t48 = load ptr, ptr %sym.addr.34, align 8
  %t49 = getelementptr inbounds %Sym, ptr %t48, i32 0, i32 4
  %t50 = load i32, ptr %t49, align 4
  %t51 = icmp ne i32 %t50, 0
  br i1 %t51, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t52 = load ptr, ptr %sym.addr.34, align 8
  %t53 = getelementptr inbounds %Sym, ptr %t52, i32 0, i32 1
  %t54 = load ptr, ptr %t53, align 8
  %t55 = load ptr, ptr %sym.addr.34, align 8
  %t56 = getelementptr inbounds %Sym, ptr %t55, i32 0, i32 5
  %t57 = load ptr, ptr %t56, align 8
  %t58 = call ptr @alloc-val(ptr %t54, ptr %t57)
  ret ptr %t58
cond.end4:
  %t59 = load ptr, ptr %sym.addr.34, align 8
  %t60 = getelementptr inbounds %Sym, ptr %t59, i32 0, i32 3
  %t61 = load i32, ptr %t60, align 4
  %t62 = icmp eq i32 %t61, 0
  br i1 %t62, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t63 = load ptr, ptr %nn.addr.0, align 8
  %t64 = getelementptr inbounds %Node, ptr %t63, i32 0, i32 1
  %t65 = load i32, ptr %t64, align 4
  %t66 = getelementptr inbounds [34 x i8], ptr @.str.80, i64 0, i64 0
  %t67 = load ptr, ptr %nn.addr.0, align 8
  %t68 = getelementptr inbounds %Node, ptr %t67, i32 0, i32 3
  %t69 = load ptr, ptr %t68, align 8
  %t70 = call ptr @fmt-s(ptr %t66, ptr %t69)
  call void @die-at(i32 %t65, ptr %t70)
  br label %cond.end5
cond.end5:
  %t72 = call ptr @new-tmp()
  store ptr %t72, ptr %tmp.addr.71, align 8
  %t73 = load ptr, ptr @g-body-stream, align 8
  %t74 = getelementptr inbounds [34 x i8], ptr @.str.81, i64 0, i64 0
  %t75 = load ptr, ptr %tmp.addr.71, align 8
  %t76 = load ptr, ptr %sym.addr.34, align 8
  %t77 = getelementptr inbounds %Sym, ptr %t76, i32 0, i32 1
  %t78 = load ptr, ptr %t77, align 8
  %t79 = call ptr @type-to-ir(ptr %t78)
  %t80 = load ptr, ptr %sym.addr.34, align 8
  %t81 = getelementptr inbounds %Sym, ptr %t80, i32 0, i32 2
  %t82 = load ptr, ptr %t81, align 8
  %t83 = load ptr, ptr %sym.addr.34, align 8
  %t84 = getelementptr inbounds %Sym, ptr %t83, i32 0, i32 1
  %t85 = load ptr, ptr %t84, align 8
  %t86 = call i32 @type-size(ptr %t85)
  %t87 = call i32 (ptr, ptr, ...) @fprintf(ptr %t73, ptr %t74, ptr %t75, ptr %t79, ptr %t82, i32 %t86)
  %t88 = load ptr, ptr %sym.addr.34, align 8
  %t89 = getelementptr inbounds %Sym, ptr %t88, i32 0, i32 1
  %t90 = load ptr, ptr %t89, align 8
  %t91 = load ptr, ptr %tmp.addr.71, align 8
  %t92 = call ptr @alloc-val(ptr %t90, ptr %t91)
  ret ptr %t92
}

define void @add-binop(ptr %name.arg, ptr %instr.arg, i32 %is-cmp.arg) {
entry:
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %instr.addr = alloca ptr, align 8
  store ptr %instr.arg, ptr %instr.addr, align 8
  %is-cmp.addr = alloca i32, align 4
  store i32 %is-cmp.arg, ptr %is-cmp.addr, align 4
  %op.addr.0 = alloca ptr, align 8
  %t1 = load ptr, ptr @g-binops, align 8
  %t2 = load i32, ptr @g-num-binops, align 4
  %t3 = sext i32 %t2 to i64
  %t4 = getelementptr inbounds %BinOp, ptr %t1, i64 %t3
  store ptr %t4, ptr %op.addr.0, align 8
  %t5 = load ptr, ptr %op.addr.0, align 8
  %t6 = load ptr, ptr %name.addr, align 8
  %t7 = getelementptr inbounds %BinOp, ptr %t5, i32 0, i32 0
  store ptr %t6, ptr %t7, align 8
  %t8 = load ptr, ptr %op.addr.0, align 8
  %t9 = load ptr, ptr %instr.addr, align 8
  %t10 = getelementptr inbounds %BinOp, ptr %t8, i32 0, i32 1
  store ptr %t9, ptr %t10, align 8
  %t11 = load ptr, ptr %op.addr.0, align 8
  %t12 = load i32, ptr %is-cmp.addr, align 4
  %t13 = getelementptr inbounds %BinOp, ptr %t11, i32 0, i32 2
  store i32 %t12, ptr %t13, align 4
  %t14 = load i32, ptr @g-num-binops, align 4
  %t15 = add nsw i32 %t14, 1
  store i32 %t15, ptr @g-num-binops, align 4
  ret void
}

define void @init-binops() {
entry:
  %t0 = sext i32 16 to i64
  %t1 = getelementptr %BinOp, ptr null, i32 1
  %t2 = ptrtoint ptr %t1 to i64
  %t3 = mul nsw i64 %t0, %t2
  %t4 = call ptr @arena-alloc(i64 %t3)
  store ptr %t4, ptr @g-binops, align 8
  %t5 = getelementptr inbounds [2 x i8], ptr @.str.82, i64 0, i64 0
  %t6 = getelementptr inbounds [8 x i8], ptr @.str.83, i64 0, i64 0
  call void @add-binop(ptr %t5, ptr %t6, i32 0)
  %t7 = getelementptr inbounds [2 x i8], ptr @.str.84, i64 0, i64 0
  %t8 = getelementptr inbounds [8 x i8], ptr @.str.85, i64 0, i64 0
  call void @add-binop(ptr %t7, ptr %t8, i32 0)
  %t9 = getelementptr inbounds [2 x i8], ptr @.str.86, i64 0, i64 0
  %t10 = getelementptr inbounds [8 x i8], ptr @.str.87, i64 0, i64 0
  call void @add-binop(ptr %t9, ptr %t10, i32 0)
  %t11 = getelementptr inbounds [2 x i8], ptr @.str.88, i64 0, i64 0
  %t12 = getelementptr inbounds [5 x i8], ptr @.str.89, i64 0, i64 0
  call void @add-binop(ptr %t11, ptr %t12, i32 0)
  %t13 = getelementptr inbounds [2 x i8], ptr @.str.90, i64 0, i64 0
  %t14 = getelementptr inbounds [5 x i8], ptr @.str.91, i64 0, i64 0
  call void @add-binop(ptr %t13, ptr %t14, i32 0)
  %t15 = getelementptr inbounds [8 x i8], ptr @.str.92, i64 0, i64 0
  %t16 = getelementptr inbounds [4 x i8], ptr @.str.93, i64 0, i64 0
  call void @add-binop(ptr %t15, ptr %t16, i32 0)
  %t17 = getelementptr inbounds [7 x i8], ptr @.str.94, i64 0, i64 0
  %t18 = getelementptr inbounds [3 x i8], ptr @.str.95, i64 0, i64 0
  call void @add-binop(ptr %t17, ptr %t18, i32 0)
  %t19 = getelementptr inbounds [8 x i8], ptr @.str.96, i64 0, i64 0
  %t20 = getelementptr inbounds [4 x i8], ptr @.str.97, i64 0, i64 0
  call void @add-binop(ptr %t19, ptr %t20, i32 0)
  %t21 = getelementptr inbounds [8 x i8], ptr @.str.98, i64 0, i64 0
  %t22 = getelementptr inbounds [4 x i8], ptr @.str.99, i64 0, i64 0
  call void @add-binop(ptr %t21, ptr %t22, i32 0)
  %t23 = getelementptr inbounds [8 x i8], ptr @.str.100, i64 0, i64 0
  %t24 = getelementptr inbounds [5 x i8], ptr @.str.101, i64 0, i64 0
  call void @add-binop(ptr %t23, ptr %t24, i32 0)
  %t25 = getelementptr inbounds [2 x i8], ptr @.str.102, i64 0, i64 0
  %t26 = getelementptr inbounds [8 x i8], ptr @.str.103, i64 0, i64 0
  call void @add-binop(ptr %t25, ptr %t26, i32 1)
  %t27 = getelementptr inbounds [3 x i8], ptr @.str.104, i64 0, i64 0
  %t28 = getelementptr inbounds [8 x i8], ptr @.str.105, i64 0, i64 0
  call void @add-binop(ptr %t27, ptr %t28, i32 1)
  %t29 = getelementptr inbounds [2 x i8], ptr @.str.106, i64 0, i64 0
  %t30 = getelementptr inbounds [9 x i8], ptr @.str.107, i64 0, i64 0
  call void @add-binop(ptr %t29, ptr %t30, i32 1)
  %t31 = getelementptr inbounds [3 x i8], ptr @.str.108, i64 0, i64 0
  %t32 = getelementptr inbounds [9 x i8], ptr @.str.109, i64 0, i64 0
  call void @add-binop(ptr %t31, ptr %t32, i32 1)
  %t33 = getelementptr inbounds [2 x i8], ptr @.str.110, i64 0, i64 0
  %t34 = getelementptr inbounds [9 x i8], ptr @.str.111, i64 0, i64 0
  call void @add-binop(ptr %t33, ptr %t34, i32 1)
  %t35 = getelementptr inbounds [3 x i8], ptr @.str.112, i64 0, i64 0
  %t36 = getelementptr inbounds [9 x i8], ptr @.str.113, i64 0, i64 0
  call void @add-binop(ptr %t35, ptr %t36, i32 1)
  ret void
}

define ptr @lookup-binop(ptr %name.arg) {
entry:
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %i.addr.0 = alloca i32, align 4
  %op.addr.4 = alloca ptr, align 8
  store i32 0, ptr %i.addr.0, align 4
  br label %while.cond0
while.cond0:
  %t1 = load i32, ptr %i.addr.0, align 4
  %t2 = load i32, ptr @g-num-binops, align 4
  %t3 = icmp slt i32 %t1, %t2
  br i1 %t3, label %while.body0, label %while.end0
while.body0:
  %t5 = load ptr, ptr @g-binops, align 8
  %t6 = load i32, ptr %i.addr.0, align 4
  %t7 = sext i32 %t6 to i64
  %t8 = getelementptr inbounds %BinOp, ptr %t5, i64 %t7
  store ptr %t8, ptr %op.addr.4, align 8
  %t9 = load ptr, ptr %op.addr.4, align 8
  %t10 = getelementptr inbounds %BinOp, ptr %t9, i32 0, i32 0
  %t11 = load ptr, ptr %t10, align 8
  %t12 = load ptr, ptr %name.addr, align 8
  %t13 = call i32 @strcmp(ptr %t11, ptr %t12)
  %t14 = icmp eq i32 %t13, 0
  br i1 %t14, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t15 = load ptr, ptr %op.addr.4, align 8
  ret ptr %t15
cond.end1:
  %t16 = load i32, ptr %i.addr.0, align 4
  %t17 = add nsw i32 %t16, 1
  store i32 %t17, ptr %i.addr.0, align 4
  br label %while.cond0
while.end0:
  ret ptr null
}

define ptr @emit-binop(ptr %call.arg, ptr %scope.arg, ptr %op.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %op.addr = alloca ptr, align 8
  store ptr %op.arg, ptr %op.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %bop.addr.2 = alloca ptr, align 8
  %a.addr.15 = alloca ptr, align 8
  %b.addr.20 = alloca ptr, align 8
  %and.val2 = alloca i1, align 1
  %tmp.addr.42 = alloca ptr, align 8
  %or.val5 = alloca i1, align 1
  %tmp.addr.98 = alloca ptr, align 8
  %rtype.addr.117 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t3 = load ptr, ptr %op.addr, align 8
  store ptr %t3, ptr %bop.addr.2, align 8
  %t4 = load ptr, ptr %cc.addr.0, align 8
  %t5 = call i32 @node-len(ptr %t4)
  %t6 = icmp ne i32 %t5, 3
  br i1 %t6, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t7 = load ptr, ptr %cc.addr.0, align 8
  %t8 = getelementptr inbounds %Node, ptr %t7, i32 0, i32 1
  %t9 = load i32, ptr %t8, align 4
  %t10 = getelementptr inbounds [18 x i8], ptr @.str.114, i64 0, i64 0
  %t11 = load ptr, ptr %bop.addr.2, align 8
  %t12 = getelementptr inbounds %BinOp, ptr %t11, i32 0, i32 0
  %t13 = load ptr, ptr %t12, align 8
  %t14 = call ptr @fmt-s(ptr %t10, ptr %t13)
  call void @die-at(i32 %t9, ptr %t14)
  br label %cond.end0
cond.end0:
  %t16 = load ptr, ptr %cc.addr.0, align 8
  %t17 = call ptr @node-at(ptr %t16, i32 1)
  %t18 = load ptr, ptr %scope.addr, align 8
  %t19 = call ptr @emit-node(ptr %t17, ptr %t18)
  store ptr %t19, ptr %a.addr.15, align 8
  %t21 = load ptr, ptr %cc.addr.0, align 8
  %t22 = call ptr @node-at(ptr %t21, i32 2)
  %t23 = load ptr, ptr %scope.addr, align 8
  %t24 = call ptr @emit-node(ptr %t22, ptr %t23)
  store ptr %t24, ptr %b.addr.20, align 8
  %t25 = load ptr, ptr %a.addr.15, align 8
  %t26 = getelementptr inbounds %Val, ptr %t25, i32 0, i32 0
  %t27 = load ptr, ptr %t26, align 8
  %t28 = getelementptr inbounds %Type, ptr %t27, i32 0, i32 0
  %t29 = load i32, ptr %t28, align 4
  %t30 = icmp eq i32 %t29, 6
  store i1 %t30, ptr %and.val2, align 1
  br i1 %t30, label %and.rhs2, label %and.end2
and.rhs2:
  %t31 = load ptr, ptr %b.addr.20, align 8
  %t32 = getelementptr inbounds %Val, ptr %t31, i32 0, i32 0
  %t33 = load ptr, ptr %t32, align 8
  %t34 = getelementptr inbounds %Type, ptr %t33, i32 0, i32 0
  %t35 = load i32, ptr %t34, align 4
  %t36 = icmp eq i32 %t35, 6
  store i1 %t36, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t37 = load i1, ptr %and.val2, align 1
  br i1 %t37, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t38 = load ptr, ptr %bop.addr.2, align 8
  %t39 = getelementptr inbounds %BinOp, ptr %t38, i32 0, i32 2
  %t40 = load i32, ptr %t39, align 4
  %t41 = icmp ne i32 %t40, 0
  br i1 %t41, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t43 = call ptr @new-tmp()
  store ptr %t43, ptr %tmp.addr.42, align 8
  %t44 = load ptr, ptr @g-body-stream, align 8
  %t45 = getelementptr inbounds [22 x i8], ptr @.str.115, i64 0, i64 0
  %t46 = load ptr, ptr %tmp.addr.42, align 8
  %t47 = load ptr, ptr %bop.addr.2, align 8
  %t48 = getelementptr inbounds %BinOp, ptr %t47, i32 0, i32 1
  %t49 = load ptr, ptr %t48, align 8
  %t50 = load ptr, ptr %a.addr.15, align 8
  %t51 = getelementptr inbounds %Val, ptr %t50, i32 0, i32 1
  %t52 = load ptr, ptr %t51, align 8
  %t53 = load ptr, ptr %b.addr.20, align 8
  %t54 = getelementptr inbounds %Val, ptr %t53, i32 0, i32 1
  %t55 = load ptr, ptr %t54, align 8
  %t56 = call i32 (ptr, ptr, ...) @fprintf(ptr %t44, ptr %t45, ptr %t46, ptr %t49, ptr %t52, ptr %t55)
  %t57 = load ptr, ptr @ty-i1, align 8
  %t58 = load ptr, ptr %tmp.addr.42, align 8
  %t59 = call ptr @alloc-val(ptr %t57, ptr %t58)
  ret ptr %t59
cond.end3:
  br label %cond.end1
cond.end1:
  %t60 = load ptr, ptr %a.addr.15, align 8
  %t61 = getelementptr inbounds %Val, ptr %t60, i32 0, i32 0
  %t62 = load ptr, ptr %t61, align 8
  %t63 = call i32 @is-int-type(ptr %t62)
  %t64 = icmp eq i32 %t63, 0
  store i1 %t64, ptr %or.val5, align 1
  br i1 %t64, label %or.end5, label %or.rhs5
or.rhs5:
  %t65 = load ptr, ptr %b.addr.20, align 8
  %t66 = getelementptr inbounds %Val, ptr %t65, i32 0, i32 0
  %t67 = load ptr, ptr %t66, align 8
  %t68 = call i32 @is-int-type(ptr %t67)
  %t69 = icmp eq i32 %t68, 0
  store i1 %t69, ptr %or.val5, align 1
  br label %or.end5
or.end5:
  %t70 = load i1, ptr %or.val5, align 1
  br i1 %t70, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t71 = load ptr, ptr %cc.addr.0, align 8
  %t72 = getelementptr inbounds %Node, ptr %t71, i32 0, i32 1
  %t73 = load i32, ptr %t72, align 4
  %t74 = getelementptr inbounds [28 x i8], ptr @.str.116, i64 0, i64 0
  %t75 = load ptr, ptr %bop.addr.2, align 8
  %t76 = getelementptr inbounds %BinOp, ptr %t75, i32 0, i32 0
  %t77 = load ptr, ptr %t76, align 8
  %t78 = call ptr @fmt-s(ptr %t74, ptr %t77)
  call void @die-at(i32 %t73, ptr %t78)
  br label %cond.end4
cond.end4:
  %t79 = load ptr, ptr %a.addr.15, align 8
  %t80 = getelementptr inbounds %Val, ptr %t79, i32 0, i32 0
  %t81 = load ptr, ptr %t80, align 8
  %t82 = getelementptr inbounds %Type, ptr %t81, i32 0, i32 0
  %t83 = load i32, ptr %t82, align 4
  %t84 = load ptr, ptr %b.addr.20, align 8
  %t85 = getelementptr inbounds %Val, ptr %t84, i32 0, i32 0
  %t86 = load ptr, ptr %t85, align 8
  %t87 = getelementptr inbounds %Type, ptr %t86, i32 0, i32 0
  %t88 = load i32, ptr %t87, align 4
  %t89 = icmp ne i32 %t83, %t88
  br i1 %t89, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t90 = load ptr, ptr %cc.addr.0, align 8
  %t91 = getelementptr inbounds %Node, ptr %t90, i32 0, i32 1
  %t92 = load i32, ptr %t91, align 4
  %t93 = getelementptr inbounds [25 x i8], ptr @.str.117, i64 0, i64 0
  %t94 = load ptr, ptr %bop.addr.2, align 8
  %t95 = getelementptr inbounds %BinOp, ptr %t94, i32 0, i32 0
  %t96 = load ptr, ptr %t95, align 8
  %t97 = call ptr @fmt-s(ptr %t93, ptr %t96)
  call void @die-at(i32 %t92, ptr %t97)
  br label %cond.end6
cond.end6:
  %t99 = call ptr @new-tmp()
  store ptr %t99, ptr %tmp.addr.98, align 8
  %t100 = load ptr, ptr @g-body-stream, align 8
  %t101 = getelementptr inbounds [21 x i8], ptr @.str.118, i64 0, i64 0
  %t102 = load ptr, ptr %tmp.addr.98, align 8
  %t103 = load ptr, ptr %bop.addr.2, align 8
  %t104 = getelementptr inbounds %BinOp, ptr %t103, i32 0, i32 1
  %t105 = load ptr, ptr %t104, align 8
  %t106 = load ptr, ptr %a.addr.15, align 8
  %t107 = getelementptr inbounds %Val, ptr %t106, i32 0, i32 0
  %t108 = load ptr, ptr %t107, align 8
  %t109 = call ptr @type-to-ir(ptr %t108)
  %t110 = load ptr, ptr %a.addr.15, align 8
  %t111 = getelementptr inbounds %Val, ptr %t110, i32 0, i32 1
  %t112 = load ptr, ptr %t111, align 8
  %t113 = load ptr, ptr %b.addr.20, align 8
  %t114 = getelementptr inbounds %Val, ptr %t113, i32 0, i32 1
  %t115 = load ptr, ptr %t114, align 8
  %t116 = call i32 (ptr, ptr, ...) @fprintf(ptr %t100, ptr %t101, ptr %t102, ptr %t105, ptr %t109, ptr %t112, ptr %t115)
  %t118 = load ptr, ptr %a.addr.15, align 8
  %t119 = getelementptr inbounds %Val, ptr %t118, i32 0, i32 0
  %t120 = load ptr, ptr %t119, align 8
  store ptr %t120, ptr %rtype.addr.117, align 8
  %t121 = load ptr, ptr %bop.addr.2, align 8
  %t122 = getelementptr inbounds %BinOp, ptr %t121, i32 0, i32 2
  %t123 = load i32, ptr %t122, align 4
  %t124 = icmp ne i32 %t123, 0
  br i1 %t124, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t125 = load ptr, ptr @ty-i1, align 8
  store ptr %t125, ptr %rtype.addr.117, align 8
  br label %cond.end7
cond.end7:
  %t126 = load ptr, ptr %rtype.addr.117, align 8
  %t127 = load ptr, ptr %tmp.addr.98, align 8
  %t128 = call ptr @alloc-val(ptr %t126, ptr %t127)
  ret ptr %t128
}

define ptr @emit-cast(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %type-node.addr.9 = alloca ptr, align 8
  %dst.addr.20 = alloca ptr, align 8
  %v.addr.28 = alloca ptr, align 8
  %src.addr.33 = alloca ptr, align 8
  %instr.addr.49 = alloca ptr, align 8
  %and.val4 = alloca i1, align 1
  %sw.addr.57 = alloca i32, align 4
  %dw.addr.60 = alloca i32, align 4
  %and.val7 = alloca i1, align 1
  %and.val9 = alloca i1, align 1
  %tmp.addr.92 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 3
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [20 x i8], ptr @.str.119, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %type-node.addr.9, align 8
  %t12 = load ptr, ptr %type-node.addr.9, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp ne i32 %t14, 2
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %type-node.addr.9, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = getelementptr inbounds [35 x i8], ptr @.str.120, i64 0, i64 0
  call void @die-at(i32 %t18, ptr %t19)
  br label %cond.end1
cond.end1:
  %t21 = load ptr, ptr %type-node.addr.9, align 8
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 3
  %t23 = load ptr, ptr %t22, align 8
  %t24 = load ptr, ptr %type-node.addr.9, align 8
  %t25 = getelementptr inbounds %Node, ptr %t24, i32 0, i32 1
  %t26 = load i32, ptr %t25, align 4
  %t27 = call ptr @parse-type-name(ptr %t23, i32 %t26)
  store ptr %t27, ptr %dst.addr.20, align 8
  %t29 = load ptr, ptr %cc.addr.0, align 8
  %t30 = call ptr @node-at(ptr %t29, i32 2)
  %t31 = load ptr, ptr %scope.addr, align 8
  %t32 = call ptr @emit-node(ptr %t30, ptr %t31)
  store ptr %t32, ptr %v.addr.28, align 8
  %t34 = load ptr, ptr %v.addr.28, align 8
  %t35 = getelementptr inbounds %Val, ptr %t34, i32 0, i32 0
  %t36 = load ptr, ptr %t35, align 8
  store ptr %t36, ptr %src.addr.33, align 8
  %t37 = load ptr, ptr %src.addr.33, align 8
  %t38 = getelementptr inbounds %Type, ptr %t37, i32 0, i32 0
  %t39 = load i32, ptr %t38, align 4
  %t40 = load ptr, ptr %dst.addr.20, align 8
  %t41 = getelementptr inbounds %Type, ptr %t40, i32 0, i32 0
  %t42 = load i32, ptr %t41, align 4
  %t43 = icmp eq i32 %t39, %t42
  br i1 %t43, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t44 = load ptr, ptr %dst.addr.20, align 8
  %t45 = load ptr, ptr %v.addr.28, align 8
  %t46 = getelementptr inbounds %Val, ptr %t45, i32 0, i32 1
  %t47 = load ptr, ptr %t46, align 8
  %t48 = call ptr @alloc-val(ptr %t44, ptr %t47)
  ret ptr %t48
cond.end2:
  store ptr null, ptr %instr.addr.49, align 8
  %t50 = load ptr, ptr %src.addr.33, align 8
  %t51 = call i32 @is-int-type(ptr %t50)
  %t52 = icmp ne i32 %t51, 0
  store i1 %t52, ptr %and.val4, align 1
  br i1 %t52, label %and.rhs4, label %and.end4
and.rhs4:
  %t53 = load ptr, ptr %dst.addr.20, align 8
  %t54 = call i32 @is-int-type(ptr %t53)
  %t55 = icmp ne i32 %t54, 0
  store i1 %t55, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t56 = load i1, ptr %and.val4, align 1
  br i1 %t56, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t58 = load ptr, ptr %src.addr.33, align 8
  %t59 = call i32 @int-width(ptr %t58)
  store i32 %t59, ptr %sw.addr.57, align 4
  %t61 = load ptr, ptr %dst.addr.20, align 8
  %t62 = call i32 @int-width(ptr %t61)
  store i32 %t62, ptr %dw.addr.60, align 4
  %t63 = load i32, ptr %dw.addr.60, align 4
  %t64 = load i32, ptr %sw.addr.57, align 4
  %t65 = icmp slt i32 %t63, %t64
  br i1 %t65, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t66 = getelementptr inbounds [6 x i8], ptr @.str.121, i64 0, i64 0
  store ptr %t66, ptr %instr.addr.49, align 8
  br label %cond.end5
cond.test5.1:
  br i1 1, label %cond.then5.1, label %cond.end5
cond.then5.1:
  %t67 = getelementptr inbounds [5 x i8], ptr @.str.122, i64 0, i64 0
  store ptr %t67, ptr %instr.addr.49, align 8
  br label %cond.end5
cond.end5:
  br label %cond.end3
cond.end3:
  %t68 = load ptr, ptr %src.addr.33, align 8
  %t69 = call i32 @is-int-type(ptr %t68)
  %t70 = icmp ne i32 %t69, 0
  store i1 %t70, ptr %and.val7, align 1
  br i1 %t70, label %and.rhs7, label %and.end7
and.rhs7:
  %t71 = load ptr, ptr %dst.addr.20, align 8
  %t72 = getelementptr inbounds %Type, ptr %t71, i32 0, i32 0
  %t73 = load i32, ptr %t72, align 4
  %t74 = icmp eq i32 %t73, 6
  store i1 %t74, ptr %and.val7, align 1
  br label %and.end7
and.end7:
  %t75 = load i1, ptr %and.val7, align 1
  br i1 %t75, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t76 = getelementptr inbounds [9 x i8], ptr @.str.123, i64 0, i64 0
  store ptr %t76, ptr %instr.addr.49, align 8
  br label %cond.end6
cond.end6:
  %t77 = load ptr, ptr %src.addr.33, align 8
  %t78 = getelementptr inbounds %Type, ptr %t77, i32 0, i32 0
  %t79 = load i32, ptr %t78, align 4
  %t80 = icmp eq i32 %t79, 6
  store i1 %t80, ptr %and.val9, align 1
  br i1 %t80, label %and.rhs9, label %and.end9
and.rhs9:
  %t81 = load ptr, ptr %dst.addr.20, align 8
  %t82 = call i32 @is-int-type(ptr %t81)
  %t83 = icmp ne i32 %t82, 0
  store i1 %t83, ptr %and.val9, align 1
  br label %and.end9
and.end9:
  %t84 = load i1, ptr %and.val9, align 1
  br i1 %t84, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t85 = getelementptr inbounds [9 x i8], ptr @.str.124, i64 0, i64 0
  store ptr %t85, ptr %instr.addr.49, align 8
  br label %cond.end8
cond.end8:
  %t86 = load ptr, ptr %instr.addr.49, align 8
  %t87 = icmp eq ptr %t86, null
  br i1 %t87, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t88 = load ptr, ptr %cc.addr.0, align 8
  %t89 = getelementptr inbounds %Node, ptr %t88, i32 0, i32 1
  %t90 = load i32, ptr %t89, align 4
  %t91 = getelementptr inbounds [29 x i8], ptr @.str.125, i64 0, i64 0
  call void @die-at(i32 %t90, ptr %t91)
  br label %cond.end10
cond.end10:
  %t93 = call ptr @new-tmp()
  store ptr %t93, ptr %tmp.addr.92, align 8
  %t94 = load ptr, ptr @g-body-stream, align 8
  %t95 = getelementptr inbounds [23 x i8], ptr @.str.126, i64 0, i64 0
  %t96 = load ptr, ptr %tmp.addr.92, align 8
  %t97 = load ptr, ptr %instr.addr.49, align 8
  %t98 = load ptr, ptr %src.addr.33, align 8
  %t99 = call ptr @type-to-ir(ptr %t98)
  %t100 = load ptr, ptr %v.addr.28, align 8
  %t101 = getelementptr inbounds %Val, ptr %t100, i32 0, i32 1
  %t102 = load ptr, ptr %t101, align 8
  %t103 = load ptr, ptr %dst.addr.20, align 8
  %t104 = call ptr @type-to-ir(ptr %t103)
  %t105 = call i32 (ptr, ptr, ...) @fprintf(ptr %t94, ptr %t95, ptr %t96, ptr %t97, ptr %t99, ptr %t102, ptr %t104)
  %t106 = load ptr, ptr %dst.addr.20, align 8
  %t107 = load ptr, ptr %tmp.addr.92, align 8
  %t108 = call ptr @alloc-val(ptr %t106, ptr %t107)
  ret ptr %t108
}

define ptr @emit-field-get(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %p.addr.9 = alloca ptr, align 8
  %pt.addr.14 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %or.val3 = alloca i1, align 1
  %fn-node.addr.38 = alloca ptr, align 8
  %sd.addr.49 = alloca ptr, align 8
  %idx.addr.55 = alloca i32, align 4
  %i.addr.56 = alloca i32, align 4
  %ftype.addr.93 = alloca ptr, align 8
  %gep.addr.101 = alloca ptr, align 8
  %val.addr.114 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 3
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [17 x i8], ptr @.str.127, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %p.addr.9, align 8
  %t15 = load ptr, ptr %p.addr.9, align 8
  %t16 = getelementptr inbounds %Val, ptr %t15, i32 0, i32 0
  %t17 = load ptr, ptr %t16, align 8
  store ptr %t17, ptr %pt.addr.14, align 8
  %t18 = load ptr, ptr %pt.addr.14, align 8
  %t19 = getelementptr inbounds %Type, ptr %t18, i32 0, i32 0
  %t20 = load i32, ptr %t19, align 4
  %t21 = icmp ne i32 %t20, 6
  store i1 %t21, ptr %or.val3, align 1
  br i1 %t21, label %or.end3, label %or.rhs3
or.rhs3:
  %t22 = load ptr, ptr %pt.addr.14, align 8
  %t23 = getelementptr inbounds %Type, ptr %t22, i32 0, i32 5
  %t24 = load ptr, ptr %t23, align 8
  %t25 = icmp eq ptr %t24, null
  store i1 %t25, ptr %or.val3, align 1
  br label %or.end3
or.end3:
  %t26 = load i1, ptr %or.val3, align 1
  store i1 %t26, ptr %or.val2, align 1
  br i1 %t26, label %or.end2, label %or.rhs2
or.rhs2:
  %t27 = load ptr, ptr %pt.addr.14, align 8
  %t28 = getelementptr inbounds %Type, ptr %t27, i32 0, i32 5
  %t29 = load ptr, ptr %t28, align 8
  %t30 = getelementptr inbounds %Type, ptr %t29, i32 0, i32 0
  %t31 = load i32, ptr %t30, align 4
  %t32 = icmp ne i32 %t31, 8
  store i1 %t32, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t33 = load i1, ptr %or.val2, align 1
  br i1 %t33, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t34 = load ptr, ptr %cc.addr.0, align 8
  %t35 = getelementptr inbounds %Node, ptr %t34, i32 0, i32 1
  %t36 = load i32, ptr %t35, align 4
  %t37 = getelementptr inbounds [37 x i8], ptr @.str.128, i64 0, i64 0
  call void @die-at(i32 %t36, ptr %t37)
  br label %cond.end1
cond.end1:
  %t39 = load ptr, ptr %cc.addr.0, align 8
  %t40 = call ptr @node-at(ptr %t39, i32 2)
  store ptr %t40, ptr %fn-node.addr.38, align 8
  %t41 = load ptr, ptr %fn-node.addr.38, align 8
  %t42 = getelementptr inbounds %Node, ptr %t41, i32 0, i32 0
  %t43 = load i32, ptr %t42, align 4
  %t44 = icmp ne i32 %t43, 2
  br i1 %t44, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t45 = load ptr, ptr %fn-node.addr.38, align 8
  %t46 = getelementptr inbounds %Node, ptr %t45, i32 0, i32 1
  %t47 = load i32, ptr %t46, align 4
  %t48 = getelementptr inbounds [29 x i8], ptr @.str.129, i64 0, i64 0
  call void @die-at(i32 %t47, ptr %t48)
  br label %cond.end4
cond.end4:
  %t50 = load ptr, ptr %pt.addr.14, align 8
  %t51 = getelementptr inbounds %Type, ptr %t50, i32 0, i32 5
  %t52 = load ptr, ptr %t51, align 8
  %t53 = getelementptr inbounds %Type, ptr %t52, i32 0, i32 6
  %t54 = load ptr, ptr %t53, align 8
  store ptr %t54, ptr %sd.addr.49, align 8
  store i32 -1, ptr %idx.addr.55, align 4
  store i32 0, ptr %i.addr.56, align 4
  br label %while.cond5
while.cond5:
  %t57 = load i32, ptr %i.addr.56, align 4
  %t58 = load ptr, ptr %sd.addr.49, align 8
  %t59 = getelementptr inbounds %StructDef, ptr %t58, i32 0, i32 3
  %t60 = load i32, ptr %t59, align 4
  %t61 = icmp slt i32 %t57, %t60
  br i1 %t61, label %while.body5, label %while.end5
while.body5:
  %t62 = load ptr, ptr %sd.addr.49, align 8
  %t63 = getelementptr inbounds %StructDef, ptr %t62, i32 0, i32 1
  %t64 = load ptr, ptr %t63, align 8
  %t65 = load i32, ptr %i.addr.56, align 4
  %t66 = sext i32 %t65 to i64
  %t67 = getelementptr inbounds ptr, ptr %t64, i64 %t66
  %t68 = load ptr, ptr %t67, align 8
  %t69 = load ptr, ptr %fn-node.addr.38, align 8
  %t70 = getelementptr inbounds %Node, ptr %t69, i32 0, i32 3
  %t71 = load ptr, ptr %t70, align 8
  %t72 = call i32 @strcmp(ptr %t68, ptr %t71)
  %t73 = icmp eq i32 %t72, 0
  br i1 %t73, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t74 = load i32, ptr %i.addr.56, align 4
  store i32 %t74, ptr %idx.addr.55, align 4
  %t75 = load ptr, ptr %sd.addr.49, align 8
  %t76 = getelementptr inbounds %StructDef, ptr %t75, i32 0, i32 3
  %t77 = load i32, ptr %t76, align 4
  store i32 %t77, ptr %i.addr.56, align 4
  br label %cond.end6
cond.end6:
  %t78 = load i32, ptr %i.addr.56, align 4
  %t79 = add nsw i32 %t78, 1
  store i32 %t79, ptr %i.addr.56, align 4
  br label %while.cond5
while.end5:
  %t80 = load i32, ptr %idx.addr.55, align 4
  %t81 = icmp slt i32 %t80, 0
  br i1 %t81, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t82 = load ptr, ptr %fn-node.addr.38, align 8
  %t83 = getelementptr inbounds %Node, ptr %t82, i32 0, i32 1
  %t84 = load i32, ptr %t83, align 4
  %t85 = getelementptr inbounds [32 x i8], ptr @.str.130, i64 0, i64 0
  %t86 = load ptr, ptr %fn-node.addr.38, align 8
  %t87 = getelementptr inbounds %Node, ptr %t86, i32 0, i32 3
  %t88 = load ptr, ptr %t87, align 8
  %t89 = load ptr, ptr %sd.addr.49, align 8
  %t90 = getelementptr inbounds %StructDef, ptr %t89, i32 0, i32 0
  %t91 = load ptr, ptr %t90, align 8
  %t92 = call ptr @fmt-2s(ptr %t85, ptr %t88, ptr %t91)
  call void @die-at(i32 %t84, ptr %t92)
  br label %cond.end7
cond.end7:
  %t94 = load ptr, ptr %sd.addr.49, align 8
  %t95 = getelementptr inbounds %StructDef, ptr %t94, i32 0, i32 2
  %t96 = load ptr, ptr %t95, align 8
  %t97 = load i32, ptr %idx.addr.55, align 4
  %t98 = sext i32 %t97 to i64
  %t99 = getelementptr inbounds ptr, ptr %t96, i64 %t98
  %t100 = load ptr, ptr %t99, align 8
  store ptr %t100, ptr %ftype.addr.93, align 8
  %t102 = call ptr @new-tmp()
  store ptr %t102, ptr %gep.addr.101, align 8
  %t103 = load ptr, ptr @g-body-stream, align 8
  %t104 = getelementptr inbounds [59 x i8], ptr @.str.131, i64 0, i64 0
  %t105 = load ptr, ptr %gep.addr.101, align 8
  %t106 = load ptr, ptr %sd.addr.49, align 8
  %t107 = getelementptr inbounds %StructDef, ptr %t106, i32 0, i32 0
  %t108 = load ptr, ptr %t107, align 8
  %t109 = load ptr, ptr %p.addr.9, align 8
  %t110 = getelementptr inbounds %Val, ptr %t109, i32 0, i32 1
  %t111 = load ptr, ptr %t110, align 8
  %t112 = load i32, ptr %idx.addr.55, align 4
  %t113 = call i32 (ptr, ptr, ...) @fprintf(ptr %t103, ptr %t104, ptr %t105, ptr %t108, ptr %t111, i32 %t112)
  %t115 = call ptr @new-tmp()
  store ptr %t115, ptr %val.addr.114, align 8
  %t116 = load ptr, ptr @g-body-stream, align 8
  %t117 = getelementptr inbounds [34 x i8], ptr @.str.132, i64 0, i64 0
  %t118 = load ptr, ptr %val.addr.114, align 8
  %t119 = load ptr, ptr %ftype.addr.93, align 8
  %t120 = call ptr @type-to-ir(ptr %t119)
  %t121 = load ptr, ptr %gep.addr.101, align 8
  %t122 = load ptr, ptr %ftype.addr.93, align 8
  %t123 = call i32 @type-size(ptr %t122)
  %t124 = call i32 (ptr, ptr, ...) @fprintf(ptr %t116, ptr %t117, ptr %t118, ptr %t120, ptr %t121, i32 %t123)
  %t125 = load ptr, ptr %ftype.addr.93, align 8
  %t126 = load ptr, ptr %val.addr.114, align 8
  %t127 = call ptr @alloc-val(ptr %t125, ptr %t126)
  ret ptr %t127
}

define ptr @emit-field-set(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %p.addr.9 = alloca ptr, align 8
  %pt.addr.14 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %or.val3 = alloca i1, align 1
  %fn-node.addr.38 = alloca ptr, align 8
  %sd.addr.49 = alloca ptr, align 8
  %idx.addr.55 = alloca i32, align 4
  %i.addr.56 = alloca i32, align 4
  %ftype.addr.93 = alloca ptr, align 8
  %v.addr.101 = alloca ptr, align 8
  %gep.addr.123 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 4
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [21 x i8], ptr @.str.133, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %p.addr.9, align 8
  %t15 = load ptr, ptr %p.addr.9, align 8
  %t16 = getelementptr inbounds %Val, ptr %t15, i32 0, i32 0
  %t17 = load ptr, ptr %t16, align 8
  store ptr %t17, ptr %pt.addr.14, align 8
  %t18 = load ptr, ptr %pt.addr.14, align 8
  %t19 = getelementptr inbounds %Type, ptr %t18, i32 0, i32 0
  %t20 = load i32, ptr %t19, align 4
  %t21 = icmp ne i32 %t20, 6
  store i1 %t21, ptr %or.val3, align 1
  br i1 %t21, label %or.end3, label %or.rhs3
or.rhs3:
  %t22 = load ptr, ptr %pt.addr.14, align 8
  %t23 = getelementptr inbounds %Type, ptr %t22, i32 0, i32 5
  %t24 = load ptr, ptr %t23, align 8
  %t25 = icmp eq ptr %t24, null
  store i1 %t25, ptr %or.val3, align 1
  br label %or.end3
or.end3:
  %t26 = load i1, ptr %or.val3, align 1
  store i1 %t26, ptr %or.val2, align 1
  br i1 %t26, label %or.end2, label %or.rhs2
or.rhs2:
  %t27 = load ptr, ptr %pt.addr.14, align 8
  %t28 = getelementptr inbounds %Type, ptr %t27, i32 0, i32 5
  %t29 = load ptr, ptr %t28, align 8
  %t30 = getelementptr inbounds %Type, ptr %t29, i32 0, i32 0
  %t31 = load i32, ptr %t30, align 4
  %t32 = icmp ne i32 %t31, 8
  store i1 %t32, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t33 = load i1, ptr %or.val2, align 1
  br i1 %t33, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t34 = load ptr, ptr %cc.addr.0, align 8
  %t35 = getelementptr inbounds %Node, ptr %t34, i32 0, i32 1
  %t36 = load i32, ptr %t35, align 4
  %t37 = getelementptr inbounds [41 x i8], ptr @.str.134, i64 0, i64 0
  call void @die-at(i32 %t36, ptr %t37)
  br label %cond.end1
cond.end1:
  %t39 = load ptr, ptr %cc.addr.0, align 8
  %t40 = call ptr @node-at(ptr %t39, i32 2)
  store ptr %t40, ptr %fn-node.addr.38, align 8
  %t41 = load ptr, ptr %fn-node.addr.38, align 8
  %t42 = getelementptr inbounds %Node, ptr %t41, i32 0, i32 0
  %t43 = load i32, ptr %t42, align 4
  %t44 = icmp ne i32 %t43, 2
  br i1 %t44, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t45 = load ptr, ptr %fn-node.addr.38, align 8
  %t46 = getelementptr inbounds %Node, ptr %t45, i32 0, i32 1
  %t47 = load i32, ptr %t46, align 4
  %t48 = getelementptr inbounds [33 x i8], ptr @.str.135, i64 0, i64 0
  call void @die-at(i32 %t47, ptr %t48)
  br label %cond.end4
cond.end4:
  %t50 = load ptr, ptr %pt.addr.14, align 8
  %t51 = getelementptr inbounds %Type, ptr %t50, i32 0, i32 5
  %t52 = load ptr, ptr %t51, align 8
  %t53 = getelementptr inbounds %Type, ptr %t52, i32 0, i32 6
  %t54 = load ptr, ptr %t53, align 8
  store ptr %t54, ptr %sd.addr.49, align 8
  store i32 -1, ptr %idx.addr.55, align 4
  store i32 0, ptr %i.addr.56, align 4
  br label %while.cond5
while.cond5:
  %t57 = load i32, ptr %i.addr.56, align 4
  %t58 = load ptr, ptr %sd.addr.49, align 8
  %t59 = getelementptr inbounds %StructDef, ptr %t58, i32 0, i32 3
  %t60 = load i32, ptr %t59, align 4
  %t61 = icmp slt i32 %t57, %t60
  br i1 %t61, label %while.body5, label %while.end5
while.body5:
  %t62 = load ptr, ptr %sd.addr.49, align 8
  %t63 = getelementptr inbounds %StructDef, ptr %t62, i32 0, i32 1
  %t64 = load ptr, ptr %t63, align 8
  %t65 = load i32, ptr %i.addr.56, align 4
  %t66 = sext i32 %t65 to i64
  %t67 = getelementptr inbounds ptr, ptr %t64, i64 %t66
  %t68 = load ptr, ptr %t67, align 8
  %t69 = load ptr, ptr %fn-node.addr.38, align 8
  %t70 = getelementptr inbounds %Node, ptr %t69, i32 0, i32 3
  %t71 = load ptr, ptr %t70, align 8
  %t72 = call i32 @strcmp(ptr %t68, ptr %t71)
  %t73 = icmp eq i32 %t72, 0
  br i1 %t73, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t74 = load i32, ptr %i.addr.56, align 4
  store i32 %t74, ptr %idx.addr.55, align 4
  %t75 = load ptr, ptr %sd.addr.49, align 8
  %t76 = getelementptr inbounds %StructDef, ptr %t75, i32 0, i32 3
  %t77 = load i32, ptr %t76, align 4
  store i32 %t77, ptr %i.addr.56, align 4
  br label %cond.end6
cond.end6:
  %t78 = load i32, ptr %i.addr.56, align 4
  %t79 = add nsw i32 %t78, 1
  store i32 %t79, ptr %i.addr.56, align 4
  br label %while.cond5
while.end5:
  %t80 = load i32, ptr %idx.addr.55, align 4
  %t81 = icmp slt i32 %t80, 0
  br i1 %t81, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t82 = load ptr, ptr %fn-node.addr.38, align 8
  %t83 = getelementptr inbounds %Node, ptr %t82, i32 0, i32 1
  %t84 = load i32, ptr %t83, align 4
  %t85 = getelementptr inbounds [36 x i8], ptr @.str.136, i64 0, i64 0
  %t86 = load ptr, ptr %fn-node.addr.38, align 8
  %t87 = getelementptr inbounds %Node, ptr %t86, i32 0, i32 3
  %t88 = load ptr, ptr %t87, align 8
  %t89 = load ptr, ptr %sd.addr.49, align 8
  %t90 = getelementptr inbounds %StructDef, ptr %t89, i32 0, i32 0
  %t91 = load ptr, ptr %t90, align 8
  %t92 = call ptr @fmt-2s(ptr %t85, ptr %t88, ptr %t91)
  call void @die-at(i32 %t84, ptr %t92)
  br label %cond.end7
cond.end7:
  %t94 = load ptr, ptr %sd.addr.49, align 8
  %t95 = getelementptr inbounds %StructDef, ptr %t94, i32 0, i32 2
  %t96 = load ptr, ptr %t95, align 8
  %t97 = load i32, ptr %idx.addr.55, align 4
  %t98 = sext i32 %t97 to i64
  %t99 = getelementptr inbounds ptr, ptr %t96, i64 %t98
  %t100 = load ptr, ptr %t99, align 8
  store ptr %t100, ptr %ftype.addr.93, align 8
  %t102 = load ptr, ptr %cc.addr.0, align 8
  %t103 = call ptr @node-at(ptr %t102, i32 3)
  %t104 = load ptr, ptr %scope.addr, align 8
  %t105 = call ptr @emit-node(ptr %t103, ptr %t104)
  store ptr %t105, ptr %v.addr.101, align 8
  %t106 = load ptr, ptr %v.addr.101, align 8
  %t107 = getelementptr inbounds %Val, ptr %t106, i32 0, i32 0
  %t108 = load ptr, ptr %t107, align 8
  %t109 = getelementptr inbounds %Type, ptr %t108, i32 0, i32 0
  %t110 = load i32, ptr %t109, align 4
  %t111 = load ptr, ptr %ftype.addr.93, align 8
  %t112 = getelementptr inbounds %Type, ptr %t111, i32 0, i32 0
  %t113 = load i32, ptr %t112, align 4
  %t114 = icmp ne i32 %t110, %t113
  br i1 %t114, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t115 = load ptr, ptr %cc.addr.0, align 8
  %t116 = getelementptr inbounds %Node, ptr %t115, i32 0, i32 1
  %t117 = load i32, ptr %t116, align 4
  %t118 = getelementptr inbounds [36 x i8], ptr @.str.137, i64 0, i64 0
  %t119 = load ptr, ptr %fn-node.addr.38, align 8
  %t120 = getelementptr inbounds %Node, ptr %t119, i32 0, i32 3
  %t121 = load ptr, ptr %t120, align 8
  %t122 = call ptr @fmt-s(ptr %t118, ptr %t121)
  call void @die-at(i32 %t117, ptr %t122)
  br label %cond.end8
cond.end8:
  %t124 = call ptr @new-tmp()
  store ptr %t124, ptr %gep.addr.123, align 8
  %t125 = load ptr, ptr @g-body-stream, align 8
  %t126 = getelementptr inbounds [59 x i8], ptr @.str.138, i64 0, i64 0
  %t127 = load ptr, ptr %gep.addr.123, align 8
  %t128 = load ptr, ptr %sd.addr.49, align 8
  %t129 = getelementptr inbounds %StructDef, ptr %t128, i32 0, i32 0
  %t130 = load ptr, ptr %t129, align 8
  %t131 = load ptr, ptr %p.addr.9, align 8
  %t132 = getelementptr inbounds %Val, ptr %t131, i32 0, i32 1
  %t133 = load ptr, ptr %t132, align 8
  %t134 = load i32, ptr %idx.addr.55, align 4
  %t135 = call i32 (ptr, ptr, ...) @fprintf(ptr %t125, ptr %t126, ptr %t127, ptr %t130, ptr %t133, i32 %t134)
  %t136 = load ptr, ptr @g-body-stream, align 8
  %t137 = getelementptr inbounds [33 x i8], ptr @.str.139, i64 0, i64 0
  %t138 = load ptr, ptr %ftype.addr.93, align 8
  %t139 = call ptr @type-to-ir(ptr %t138)
  %t140 = load ptr, ptr %v.addr.101, align 8
  %t141 = getelementptr inbounds %Val, ptr %t140, i32 0, i32 1
  %t142 = load ptr, ptr %t141, align 8
  %t143 = load ptr, ptr %gep.addr.123, align 8
  %t144 = load ptr, ptr %ftype.addr.93, align 8
  %t145 = call i32 @type-size(ptr %t144)
  %t146 = call i32 (ptr, ptr, ...) @fprintf(ptr %t136, ptr %t137, ptr %t139, ptr %t142, ptr %t143, i32 %t145)
  %t147 = load ptr, ptr @ty-void, align 8
  %t148 = call ptr @alloc-val(ptr %t147, ptr null)
  ret ptr %t148
}

define ptr @emit-sizeof(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %tn.addr.9 = alloca ptr, align 8
  %ty.addr.20 = alloca ptr, align 8
  %gep.addr.28 = alloca ptr, align 8
  %sz.addr.36 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [21 x i8], ptr @.str.140, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %tn.addr.9, align 8
  %t12 = load ptr, ptr %tn.addr.9, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp ne i32 %t14, 2
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %tn.addr.9, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = getelementptr inbounds [30 x i8], ptr @.str.141, i64 0, i64 0
  call void @die-at(i32 %t18, ptr %t19)
  br label %cond.end1
cond.end1:
  %t21 = load ptr, ptr %tn.addr.9, align 8
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 3
  %t23 = load ptr, ptr %t22, align 8
  %t24 = load ptr, ptr %tn.addr.9, align 8
  %t25 = getelementptr inbounds %Node, ptr %t24, i32 0, i32 1
  %t26 = load i32, ptr %t25, align 4
  %t27 = call ptr @parse-type-name(ptr %t23, i32 %t26)
  store ptr %t27, ptr %ty.addr.20, align 8
  %t29 = call ptr @new-tmp()
  store ptr %t29, ptr %gep.addr.28, align 8
  %t30 = load ptr, ptr @g-body-stream, align 8
  %t31 = getelementptr inbounds [42 x i8], ptr @.str.142, i64 0, i64 0
  %t32 = load ptr, ptr %gep.addr.28, align 8
  %t33 = load ptr, ptr %ty.addr.20, align 8
  %t34 = call ptr @type-to-ir(ptr %t33)
  %t35 = call i32 (ptr, ptr, ...) @fprintf(ptr %t30, ptr %t31, ptr %t32, ptr %t34)
  %t37 = call ptr @new-tmp()
  store ptr %t37, ptr %sz.addr.36, align 8
  %t38 = load ptr, ptr @g-body-stream, align 8
  %t39 = getelementptr inbounds [31 x i8], ptr @.str.143, i64 0, i64 0
  %t40 = load ptr, ptr %sz.addr.36, align 8
  %t41 = load ptr, ptr %gep.addr.28, align 8
  %t42 = call i32 (ptr, ptr, ...) @fprintf(ptr %t38, ptr %t39, ptr %t40, ptr %t41)
  %t43 = load ptr, ptr @ty-i64, align 8
  %t44 = load ptr, ptr %sz.addr.36, align 8
  %t45 = call ptr @alloc-val(ptr %t43, ptr %t44)
  ret ptr %t45
}

define ptr @emit-alloca-form(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %and.val1 = alloca i1, align 1
  %tn.addr.13 = alloca ptr, align 8
  %ty.addr.24 = alloca ptr, align 8
  %slot.addr.32 = alloca ptr, align 8
  %pt.addr.34 = alloca ptr, align 8
  %nv.addr.42 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  store i1 %t4, ptr %and.val1, align 1
  br i1 %t4, label %and.rhs1, label %and.end1
and.rhs1:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = call i32 @node-len(ptr %t5)
  %t7 = icmp ne i32 %t6, 3
  store i1 %t7, ptr %and.val1, align 1
  br label %and.end1
and.end1:
  %t8 = load i1, ptr %and.val1, align 1
  br i1 %t8, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t9 = load ptr, ptr %cc.addr.0, align 8
  %t10 = getelementptr inbounds %Node, ptr %t9, i32 0, i32 1
  %t11 = load i32, ptr %t10, align 4
  %t12 = getelementptr inbounds [27 x i8], ptr @.str.144, i64 0, i64 0
  call void @die-at(i32 %t11, ptr %t12)
  br label %cond.end0
cond.end0:
  %t14 = load ptr, ptr %cc.addr.0, align 8
  %t15 = call ptr @node-at(ptr %t14, i32 1)
  store ptr %t15, ptr %tn.addr.13, align 8
  %t16 = load ptr, ptr %tn.addr.13, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp ne i32 %t18, 2
  br i1 %t19, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t20 = load ptr, ptr %tn.addr.13, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 1
  %t22 = load i32, ptr %t21, align 4
  %t23 = getelementptr inbounds [36 x i8], ptr @.str.145, i64 0, i64 0
  call void @die-at(i32 %t22, ptr %t23)
  br label %cond.end2
cond.end2:
  %t25 = load ptr, ptr %tn.addr.13, align 8
  %t26 = getelementptr inbounds %Node, ptr %t25, i32 0, i32 3
  %t27 = load ptr, ptr %t26, align 8
  %t28 = load ptr, ptr %tn.addr.13, align 8
  %t29 = getelementptr inbounds %Node, ptr %t28, i32 0, i32 1
  %t30 = load i32, ptr %t29, align 4
  %t31 = call ptr @parse-type-name(ptr %t27, i32 %t30)
  store ptr %t31, ptr %ty.addr.24, align 8
  %t33 = call ptr @new-tmp()
  store ptr %t33, ptr %slot.addr.32, align 8
  %t35 = call ptr @make-type(i32 6)
  store ptr %t35, ptr %pt.addr.34, align 8
  %t36 = load ptr, ptr %pt.addr.34, align 8
  %t37 = load ptr, ptr %ty.addr.24, align 8
  %t38 = getelementptr inbounds %Type, ptr %t36, i32 0, i32 5
  store ptr %t37, ptr %t38, align 8
  %t39 = load ptr, ptr %cc.addr.0, align 8
  %t40 = call i32 @node-len(ptr %t39)
  %t41 = icmp eq i32 %t40, 3
  br i1 %t41, label %cond.then3.0, label %cond.test3.1
cond.then3.0:
  %t43 = load ptr, ptr %cc.addr.0, align 8
  %t44 = call ptr @node-at(ptr %t43, i32 2)
  %t45 = load ptr, ptr %scope.addr, align 8
  %t46 = call ptr @emit-node(ptr %t44, ptr %t45)
  store ptr %t46, ptr %nv.addr.42, align 8
  %t47 = load ptr, ptr @g-body-stream, align 8
  %t48 = getelementptr inbounds [36 x i8], ptr @.str.146, i64 0, i64 0
  %t49 = load ptr, ptr %slot.addr.32, align 8
  %t50 = load ptr, ptr %ty.addr.24, align 8
  %t51 = call ptr @type-to-ir(ptr %t50)
  %t52 = load ptr, ptr %nv.addr.42, align 8
  %t53 = getelementptr inbounds %Val, ptr %t52, i32 0, i32 1
  %t54 = load ptr, ptr %t53, align 8
  %t55 = load ptr, ptr %ty.addr.24, align 8
  %t56 = call i32 @type-size(ptr %t55)
  %t57 = call i32 (ptr, ptr, ...) @fprintf(ptr %t47, ptr %t48, ptr %t49, ptr %t51, ptr %t54, i32 %t56)
  br label %cond.end3
cond.test3.1:
  br i1 1, label %cond.then3.1, label %cond.end3
cond.then3.1:
  %t58 = load ptr, ptr @g-entry-stream, align 8
  %t59 = getelementptr inbounds [28 x i8], ptr @.str.147, i64 0, i64 0
  %t60 = load ptr, ptr %slot.addr.32, align 8
  %t61 = load ptr, ptr %ty.addr.24, align 8
  %t62 = call ptr @type-to-ir(ptr %t61)
  %t63 = load ptr, ptr %ty.addr.24, align 8
  %t64 = call i32 @type-size(ptr %t63)
  %t65 = call i32 (ptr, ptr, ...) @fprintf(ptr %t58, ptr %t59, ptr %t60, ptr %t62, i32 %t64)
  br label %cond.end3
cond.end3:
  %t66 = load ptr, ptr %pt.addr.34, align 8
  %t67 = load ptr, ptr %slot.addr.32, align 8
  %t68 = call ptr @alloc-val(ptr %t66, ptr %t67)
  ret ptr %t68
}

define ptr @emit-aref(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %p.addr.9 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %idx.addr.31 = alloca ptr, align 8
  %idx64.addr.45 = alloca ptr, align 8
  %t.addr.55 = alloca ptr, align 8
  %elem.addr.69 = alloca ptr, align 8
  %gep.addr.75 = alloca ptr, align 8
  %val.addr.87 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 3
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [20 x i8], ptr @.str.148, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %p.addr.9, align 8
  %t14 = load ptr, ptr %p.addr.9, align 8
  %t15 = getelementptr inbounds %Val, ptr %t14, i32 0, i32 0
  %t16 = load ptr, ptr %t15, align 8
  %t17 = getelementptr inbounds %Type, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp ne i32 %t18, 6
  store i1 %t19, ptr %or.val2, align 1
  br i1 %t19, label %or.end2, label %or.rhs2
or.rhs2:
  %t20 = load ptr, ptr %p.addr.9, align 8
  %t21 = getelementptr inbounds %Val, ptr %t20, i32 0, i32 0
  %t22 = load ptr, ptr %t21, align 8
  %t23 = getelementptr inbounds %Type, ptr %t22, i32 0, i32 5
  %t24 = load ptr, ptr %t23, align 8
  %t25 = icmp eq ptr %t24, null
  store i1 %t25, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t26 = load i1, ptr %or.val2, align 1
  br i1 %t26, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t27 = load ptr, ptr %cc.addr.0, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 1
  %t29 = load i32, ptr %t28, align 4
  %t30 = getelementptr inbounds [36 x i8], ptr @.str.149, i64 0, i64 0
  call void @die-at(i32 %t29, ptr %t30)
  br label %cond.end1
cond.end1:
  %t32 = load ptr, ptr %cc.addr.0, align 8
  %t33 = call ptr @node-at(ptr %t32, i32 2)
  %t34 = load ptr, ptr %scope.addr, align 8
  %t35 = call ptr @emit-node(ptr %t33, ptr %t34)
  store ptr %t35, ptr %idx.addr.31, align 8
  %t36 = load ptr, ptr %idx.addr.31, align 8
  %t37 = getelementptr inbounds %Val, ptr %t36, i32 0, i32 0
  %t38 = load ptr, ptr %t37, align 8
  %t39 = call i32 @is-int-type(ptr %t38)
  %t40 = icmp eq i32 %t39, 0
  br i1 %t40, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t41 = load ptr, ptr %cc.addr.0, align 8
  %t42 = getelementptr inbounds %Node, ptr %t41, i32 0, i32 1
  %t43 = load i32, ptr %t42, align 4
  %t44 = getelementptr inbounds [28 x i8], ptr @.str.150, i64 0, i64 0
  call void @die-at(i32 %t43, ptr %t44)
  br label %cond.end3
cond.end3:
  %t46 = load ptr, ptr %idx.addr.31, align 8
  %t47 = getelementptr inbounds %Val, ptr %t46, i32 0, i32 1
  %t48 = load ptr, ptr %t47, align 8
  store ptr %t48, ptr %idx64.addr.45, align 8
  %t49 = load ptr, ptr %idx.addr.31, align 8
  %t50 = getelementptr inbounds %Val, ptr %t49, i32 0, i32 0
  %t51 = load ptr, ptr %t50, align 8
  %t52 = getelementptr inbounds %Type, ptr %t51, i32 0, i32 0
  %t53 = load i32, ptr %t52, align 4
  %t54 = icmp ne i32 %t53, 5
  br i1 %t54, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t56 = call ptr @new-tmp()
  store ptr %t56, ptr %t.addr.55, align 8
  %t57 = load ptr, ptr @g-body-stream, align 8
  %t58 = getelementptr inbounds [26 x i8], ptr @.str.151, i64 0, i64 0
  %t59 = load ptr, ptr %t.addr.55, align 8
  %t60 = load ptr, ptr %idx.addr.31, align 8
  %t61 = getelementptr inbounds %Val, ptr %t60, i32 0, i32 0
  %t62 = load ptr, ptr %t61, align 8
  %t63 = call ptr @type-to-ir(ptr %t62)
  %t64 = load ptr, ptr %idx.addr.31, align 8
  %t65 = getelementptr inbounds %Val, ptr %t64, i32 0, i32 1
  %t66 = load ptr, ptr %t65, align 8
  %t67 = call i32 (ptr, ptr, ...) @fprintf(ptr %t57, ptr %t58, ptr %t59, ptr %t63, ptr %t66)
  %t68 = load ptr, ptr %t.addr.55, align 8
  store ptr %t68, ptr %idx64.addr.45, align 8
  br label %cond.end4
cond.end4:
  %t70 = load ptr, ptr %p.addr.9, align 8
  %t71 = getelementptr inbounds %Val, ptr %t70, i32 0, i32 0
  %t72 = load ptr, ptr %t71, align 8
  %t73 = getelementptr inbounds %Type, ptr %t72, i32 0, i32 5
  %t74 = load ptr, ptr %t73, align 8
  store ptr %t74, ptr %elem.addr.69, align 8
  %t76 = call ptr @new-tmp()
  store ptr %t76, ptr %gep.addr.75, align 8
  %t77 = load ptr, ptr @g-body-stream, align 8
  %t78 = getelementptr inbounds [50 x i8], ptr @.str.152, i64 0, i64 0
  %t79 = load ptr, ptr %gep.addr.75, align 8
  %t80 = load ptr, ptr %elem.addr.69, align 8
  %t81 = call ptr @type-to-ir(ptr %t80)
  %t82 = load ptr, ptr %p.addr.9, align 8
  %t83 = getelementptr inbounds %Val, ptr %t82, i32 0, i32 1
  %t84 = load ptr, ptr %t83, align 8
  %t85 = load ptr, ptr %idx64.addr.45, align 8
  %t86 = call i32 (ptr, ptr, ...) @fprintf(ptr %t77, ptr %t78, ptr %t79, ptr %t81, ptr %t84, ptr %t85)
  %t88 = call ptr @new-tmp()
  store ptr %t88, ptr %val.addr.87, align 8
  %t89 = load ptr, ptr @g-body-stream, align 8
  %t90 = getelementptr inbounds [34 x i8], ptr @.str.153, i64 0, i64 0
  %t91 = load ptr, ptr %val.addr.87, align 8
  %t92 = load ptr, ptr %elem.addr.69, align 8
  %t93 = call ptr @type-to-ir(ptr %t92)
  %t94 = load ptr, ptr %gep.addr.75, align 8
  %t95 = load ptr, ptr %elem.addr.69, align 8
  %t96 = call i32 @type-size(ptr %t95)
  %t97 = call i32 (ptr, ptr, ...) @fprintf(ptr %t89, ptr %t90, ptr %t91, ptr %t93, ptr %t94, i32 %t96)
  %t98 = load ptr, ptr %elem.addr.69, align 8
  %t99 = load ptr, ptr %val.addr.87, align 8
  %t100 = call ptr @alloc-val(ptr %t98, ptr %t99)
  ret ptr %t100
}

define ptr @emit-aset(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %p.addr.9 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %idx.addr.31 = alloca ptr, align 8
  %idx64.addr.45 = alloca ptr, align 8
  %t.addr.55 = alloca ptr, align 8
  %elem.addr.69 = alloca ptr, align 8
  %v.addr.75 = alloca ptr, align 8
  %gep.addr.93 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 4
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [21 x i8], ptr @.str.154, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %p.addr.9, align 8
  %t14 = load ptr, ptr %p.addr.9, align 8
  %t15 = getelementptr inbounds %Val, ptr %t14, i32 0, i32 0
  %t16 = load ptr, ptr %t15, align 8
  %t17 = getelementptr inbounds %Type, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp ne i32 %t18, 6
  store i1 %t19, ptr %or.val2, align 1
  br i1 %t19, label %or.end2, label %or.rhs2
or.rhs2:
  %t20 = load ptr, ptr %p.addr.9, align 8
  %t21 = getelementptr inbounds %Val, ptr %t20, i32 0, i32 0
  %t22 = load ptr, ptr %t21, align 8
  %t23 = getelementptr inbounds %Type, ptr %t22, i32 0, i32 5
  %t24 = load ptr, ptr %t23, align 8
  %t25 = icmp eq ptr %t24, null
  store i1 %t25, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t26 = load i1, ptr %or.val2, align 1
  br i1 %t26, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t27 = load ptr, ptr %cc.addr.0, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 1
  %t29 = load i32, ptr %t28, align 4
  %t30 = getelementptr inbounds [37 x i8], ptr @.str.155, i64 0, i64 0
  call void @die-at(i32 %t29, ptr %t30)
  br label %cond.end1
cond.end1:
  %t32 = load ptr, ptr %cc.addr.0, align 8
  %t33 = call ptr @node-at(ptr %t32, i32 2)
  %t34 = load ptr, ptr %scope.addr, align 8
  %t35 = call ptr @emit-node(ptr %t33, ptr %t34)
  store ptr %t35, ptr %idx.addr.31, align 8
  %t36 = load ptr, ptr %idx.addr.31, align 8
  %t37 = getelementptr inbounds %Val, ptr %t36, i32 0, i32 0
  %t38 = load ptr, ptr %t37, align 8
  %t39 = call i32 @is-int-type(ptr %t38)
  %t40 = icmp eq i32 %t39, 0
  br i1 %t40, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t41 = load ptr, ptr %cc.addr.0, align 8
  %t42 = getelementptr inbounds %Node, ptr %t41, i32 0, i32 1
  %t43 = load i32, ptr %t42, align 4
  %t44 = getelementptr inbounds [29 x i8], ptr @.str.156, i64 0, i64 0
  call void @die-at(i32 %t43, ptr %t44)
  br label %cond.end3
cond.end3:
  %t46 = load ptr, ptr %idx.addr.31, align 8
  %t47 = getelementptr inbounds %Val, ptr %t46, i32 0, i32 1
  %t48 = load ptr, ptr %t47, align 8
  store ptr %t48, ptr %idx64.addr.45, align 8
  %t49 = load ptr, ptr %idx.addr.31, align 8
  %t50 = getelementptr inbounds %Val, ptr %t49, i32 0, i32 0
  %t51 = load ptr, ptr %t50, align 8
  %t52 = getelementptr inbounds %Type, ptr %t51, i32 0, i32 0
  %t53 = load i32, ptr %t52, align 4
  %t54 = icmp ne i32 %t53, 5
  br i1 %t54, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t56 = call ptr @new-tmp()
  store ptr %t56, ptr %t.addr.55, align 8
  %t57 = load ptr, ptr @g-body-stream, align 8
  %t58 = getelementptr inbounds [26 x i8], ptr @.str.157, i64 0, i64 0
  %t59 = load ptr, ptr %t.addr.55, align 8
  %t60 = load ptr, ptr %idx.addr.31, align 8
  %t61 = getelementptr inbounds %Val, ptr %t60, i32 0, i32 0
  %t62 = load ptr, ptr %t61, align 8
  %t63 = call ptr @type-to-ir(ptr %t62)
  %t64 = load ptr, ptr %idx.addr.31, align 8
  %t65 = getelementptr inbounds %Val, ptr %t64, i32 0, i32 1
  %t66 = load ptr, ptr %t65, align 8
  %t67 = call i32 (ptr, ptr, ...) @fprintf(ptr %t57, ptr %t58, ptr %t59, ptr %t63, ptr %t66)
  %t68 = load ptr, ptr %t.addr.55, align 8
  store ptr %t68, ptr %idx64.addr.45, align 8
  br label %cond.end4
cond.end4:
  %t70 = load ptr, ptr %p.addr.9, align 8
  %t71 = getelementptr inbounds %Val, ptr %t70, i32 0, i32 0
  %t72 = load ptr, ptr %t71, align 8
  %t73 = getelementptr inbounds %Type, ptr %t72, i32 0, i32 5
  %t74 = load ptr, ptr %t73, align 8
  store ptr %t74, ptr %elem.addr.69, align 8
  %t76 = load ptr, ptr %cc.addr.0, align 8
  %t77 = call ptr @node-at(ptr %t76, i32 3)
  %t78 = load ptr, ptr %scope.addr, align 8
  %t79 = call ptr @emit-node(ptr %t77, ptr %t78)
  store ptr %t79, ptr %v.addr.75, align 8
  %t80 = load ptr, ptr %v.addr.75, align 8
  %t81 = getelementptr inbounds %Val, ptr %t80, i32 0, i32 0
  %t82 = load ptr, ptr %t81, align 8
  %t83 = getelementptr inbounds %Type, ptr %t82, i32 0, i32 0
  %t84 = load i32, ptr %t83, align 4
  %t85 = load ptr, ptr %elem.addr.69, align 8
  %t86 = getelementptr inbounds %Type, ptr %t85, i32 0, i32 0
  %t87 = load i32, ptr %t86, align 4
  %t88 = icmp ne i32 %t84, %t87
  br i1 %t88, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t89 = load ptr, ptr %cc.addr.0, align 8
  %t90 = getelementptr inbounds %Node, ptr %t89, i32 0, i32 1
  %t91 = load i32, ptr %t90, align 4
  %t92 = getelementptr inbounds [27 x i8], ptr @.str.158, i64 0, i64 0
  call void @die-at(i32 %t91, ptr %t92)
  br label %cond.end5
cond.end5:
  %t94 = call ptr @new-tmp()
  store ptr %t94, ptr %gep.addr.93, align 8
  %t95 = load ptr, ptr @g-body-stream, align 8
  %t96 = getelementptr inbounds [50 x i8], ptr @.str.159, i64 0, i64 0
  %t97 = load ptr, ptr %gep.addr.93, align 8
  %t98 = load ptr, ptr %elem.addr.69, align 8
  %t99 = call ptr @type-to-ir(ptr %t98)
  %t100 = load ptr, ptr %p.addr.9, align 8
  %t101 = getelementptr inbounds %Val, ptr %t100, i32 0, i32 1
  %t102 = load ptr, ptr %t101, align 8
  %t103 = load ptr, ptr %idx64.addr.45, align 8
  %t104 = call i32 (ptr, ptr, ...) @fprintf(ptr %t95, ptr %t96, ptr %t97, ptr %t99, ptr %t102, ptr %t103)
  %t105 = load ptr, ptr @g-body-stream, align 8
  %t106 = getelementptr inbounds [33 x i8], ptr @.str.160, i64 0, i64 0
  %t107 = load ptr, ptr %elem.addr.69, align 8
  %t108 = call ptr @type-to-ir(ptr %t107)
  %t109 = load ptr, ptr %v.addr.75, align 8
  %t110 = getelementptr inbounds %Val, ptr %t109, i32 0, i32 1
  %t111 = load ptr, ptr %t110, align 8
  %t112 = load ptr, ptr %gep.addr.93, align 8
  %t113 = load ptr, ptr %elem.addr.69, align 8
  %t114 = call i32 @type-size(ptr %t113)
  %t115 = call i32 (ptr, ptr, ...) @fprintf(ptr %t105, ptr %t106, ptr %t108, ptr %t111, ptr %t112, i32 %t114)
  %t116 = load ptr, ptr @ty-void, align 8
  %t117 = call ptr @alloc-val(ptr %t116, ptr null)
  ret ptr %t117
}

define ptr @emit-char(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %arg.addr.9 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [19 x i8], ptr @.str.161, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %arg.addr.9, align 8
  %t12 = load ptr, ptr %arg.addr.9, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp ne i32 %t14, 1
  store i1 %t15, ptr %or.val2, align 1
  br i1 %t15, label %or.end2, label %or.rhs2
or.rhs2:
  %t16 = load ptr, ptr %arg.addr.9, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 3
  %t18 = load ptr, ptr %t17, align 8
  %t19 = call i64 @strlen(ptr %t18)
  %t20 = sext i32 1 to i64
  %t21 = icmp ne i64 %t19, %t20
  store i1 %t21, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t22 = load i1, ptr %or.val2, align 1
  br i1 %t22, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t23 = load ptr, ptr %arg.addr.9, align 8
  %t24 = getelementptr inbounds %Node, ptr %t23, i32 0, i32 1
  %t25 = load i32, ptr %t24, align 4
  %t26 = getelementptr inbounds [37 x i8], ptr @.str.162, i64 0, i64 0
  call void @die-at(i32 %t25, ptr %t26)
  br label %cond.end1
cond.end1:
  %t27 = load ptr, ptr @ty-i8, align 8
  %t28 = getelementptr inbounds [3 x i8], ptr @.str.163, i64 0, i64 0
  %t29 = load ptr, ptr %arg.addr.9, align 8
  %t30 = getelementptr inbounds %Node, ptr %t29, i32 0, i32 3
  %t31 = load ptr, ptr %t30, align 8
  %t32 = sext i32 0 to i64
  %t33 = call i32 @char-at(ptr %t31, i64 %t32)
  %t34 = call ptr @fmt-i32(ptr %t28, i32 %t33)
  %t35 = call ptr @alloc-val(ptr %t27, ptr %t34)
  ret ptr %t35
}

define ptr @emit-addr-of(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %target.addr.9 = alloca ptr, align 8
  %sym.addr.20 = alloca ptr, align 8
  %pt.addr.50 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [22 x i8], ptr @.str.164, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %target.addr.9, align 8
  %t12 = load ptr, ptr %target.addr.9, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp ne i32 %t14, 2
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %target.addr.9, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = getelementptr inbounds [31 x i8], ptr @.str.165, i64 0, i64 0
  call void @die-at(i32 %t18, ptr %t19)
  br label %cond.end1
cond.end1:
  %t21 = load ptr, ptr %scope.addr, align 8
  %t22 = load ptr, ptr %target.addr.9, align 8
  %t23 = getelementptr inbounds %Node, ptr %t22, i32 0, i32 3
  %t24 = load ptr, ptr %t23, align 8
  %t25 = call ptr @scope-lookup(ptr %t21, ptr %t24)
  store ptr %t25, ptr %sym.addr.20, align 8
  %t26 = load ptr, ptr %sym.addr.20, align 8
  %t27 = icmp eq ptr %t26, null
  br i1 %t27, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t28 = load ptr, ptr %target.addr.9, align 8
  %t29 = getelementptr inbounds %Node, ptr %t28, i32 0, i32 1
  %t30 = load i32, ptr %t29, align 4
  %t31 = getelementptr inbounds [24 x i8], ptr @.str.166, i64 0, i64 0
  %t32 = load ptr, ptr %target.addr.9, align 8
  %t33 = getelementptr inbounds %Node, ptr %t32, i32 0, i32 3
  %t34 = load ptr, ptr %t33, align 8
  %t35 = call ptr @fmt-s(ptr %t31, ptr %t34)
  call void @die-at(i32 %t30, ptr %t35)
  br label %cond.end2
cond.end2:
  %t36 = load ptr, ptr %sym.addr.20, align 8
  %t37 = getelementptr inbounds %Sym, ptr %t36, i32 0, i32 1
  %t38 = load ptr, ptr %t37, align 8
  %t39 = getelementptr inbounds %Type, ptr %t38, i32 0, i32 0
  %t40 = load i32, ptr %t39, align 4
  %t41 = icmp eq i32 %t40, 7
  br i1 %t41, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t42 = load ptr, ptr %target.addr.9, align 8
  %t43 = getelementptr inbounds %Node, ptr %t42, i32 0, i32 1
  %t44 = load i32, ptr %t43, align 4
  %t45 = getelementptr inbounds [46 x i8], ptr @.str.167, i64 0, i64 0
  %t46 = load ptr, ptr %target.addr.9, align 8
  %t47 = getelementptr inbounds %Node, ptr %t46, i32 0, i32 3
  %t48 = load ptr, ptr %t47, align 8
  %t49 = call ptr @fmt-s(ptr %t45, ptr %t48)
  call void @die-at(i32 %t44, ptr %t49)
  br label %cond.end3
cond.end3:
  %t51 = call ptr @make-type(i32 6)
  store ptr %t51, ptr %pt.addr.50, align 8
  %t52 = load ptr, ptr %pt.addr.50, align 8
  %t53 = load ptr, ptr %sym.addr.20, align 8
  %t54 = getelementptr inbounds %Sym, ptr %t53, i32 0, i32 1
  %t55 = load ptr, ptr %t54, align 8
  %t56 = getelementptr inbounds %Type, ptr %t52, i32 0, i32 5
  store ptr %t55, ptr %t56, align 8
  %t57 = load ptr, ptr %pt.addr.50, align 8
  %t58 = load ptr, ptr %sym.addr.20, align 8
  %t59 = getelementptr inbounds %Sym, ptr %t58, i32 0, i32 2
  %t60 = load ptr, ptr %t59, align 8
  %t61 = call ptr @alloc-val(ptr %t57, ptr %t60)
  ret ptr %t61
}

define ptr @emit-funcall-void(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %fn.addr.9 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [27 x i8], ptr @.str.168, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %fn.addr.9, align 8
  %t14 = load ptr, ptr %fn.addr.9, align 8
  %t15 = getelementptr inbounds %Val, ptr %t14, i32 0, i32 0
  %t16 = load ptr, ptr %t15, align 8
  %t17 = getelementptr inbounds %Type, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp ne i32 %t18, 6
  br i1 %t19, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t20 = load ptr, ptr %cc.addr.0, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 1
  %t22 = load i32, ptr %t21, align 4
  %t23 = getelementptr inbounds [30 x i8], ptr @.str.169, i64 0, i64 0
  call void @die-at(i32 %t22, ptr %t23)
  br label %cond.end1
cond.end1:
  %t24 = load ptr, ptr @g-body-stream, align 8
  %t25 = getelementptr inbounds [18 x i8], ptr @.str.170, i64 0, i64 0
  %t26 = load ptr, ptr %fn.addr.9, align 8
  %t27 = getelementptr inbounds %Val, ptr %t26, i32 0, i32 1
  %t28 = load ptr, ptr %t27, align 8
  %t29 = call i32 (ptr, ptr, ...) @fprintf(ptr %t24, ptr %t25, ptr %t28)
  %t30 = load ptr, ptr @ty-void, align 8
  %t31 = call ptr @alloc-val(ptr %t30, ptr null)
  ret ptr %t31
}

define ptr @emit-funcall-ptr-1(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %fn.addr.9 = alloca ptr, align 8
  %arg.addr.14 = alloca ptr, align 8
  %tmp.addr.39 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 3
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [29 x i8], ptr @.str.171, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %fn.addr.9, align 8
  %t15 = load ptr, ptr %cc.addr.0, align 8
  %t16 = call ptr @node-at(ptr %t15, i32 2)
  %t17 = load ptr, ptr %scope.addr, align 8
  %t18 = call ptr @emit-node(ptr %t16, ptr %t17)
  store ptr %t18, ptr %arg.addr.14, align 8
  %t19 = load ptr, ptr %fn.addr.9, align 8
  %t20 = getelementptr inbounds %Val, ptr %t19, i32 0, i32 0
  %t21 = load ptr, ptr %t20, align 8
  %t22 = getelementptr inbounds %Type, ptr %t21, i32 0, i32 0
  %t23 = load i32, ptr %t22, align 4
  %t24 = icmp ne i32 %t23, 6
  br i1 %t24, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t25 = load ptr, ptr %cc.addr.0, align 8
  %t26 = getelementptr inbounds %Node, ptr %t25, i32 0, i32 1
  %t27 = load i32, ptr %t26, align 4
  %t28 = getelementptr inbounds [30 x i8], ptr @.str.172, i64 0, i64 0
  call void @die-at(i32 %t27, ptr %t28)
  br label %cond.end1
cond.end1:
  %t29 = load ptr, ptr %arg.addr.14, align 8
  %t30 = getelementptr inbounds %Val, ptr %t29, i32 0, i32 0
  %t31 = load ptr, ptr %t30, align 8
  %t32 = getelementptr inbounds %Type, ptr %t31, i32 0, i32 0
  %t33 = load i32, ptr %t32, align 4
  %t34 = icmp ne i32 %t33, 6
  br i1 %t34, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t35 = load ptr, ptr %cc.addr.0, align 8
  %t36 = getelementptr inbounds %Node, ptr %t35, i32 0, i32 1
  %t37 = load i32, ptr %t36, align 4
  %t38 = getelementptr inbounds [31 x i8], ptr @.str.173, i64 0, i64 0
  call void @die-at(i32 %t37, ptr %t38)
  br label %cond.end2
cond.end2:
  %t40 = call ptr @new-tmp()
  store ptr %t40, ptr %tmp.addr.39, align 8
  %t41 = load ptr, ptr @g-body-stream, align 8
  %t42 = getelementptr inbounds [28 x i8], ptr @.str.174, i64 0, i64 0
  %t43 = load ptr, ptr %tmp.addr.39, align 8
  %t44 = load ptr, ptr %fn.addr.9, align 8
  %t45 = getelementptr inbounds %Val, ptr %t44, i32 0, i32 1
  %t46 = load ptr, ptr %t45, align 8
  %t47 = load ptr, ptr %arg.addr.14, align 8
  %t48 = getelementptr inbounds %Val, ptr %t47, i32 0, i32 1
  %t49 = load ptr, ptr %t48, align 8
  %t50 = call i32 (ptr, ptr, ...) @fprintf(ptr %t41, ptr %t42, ptr %t43, ptr %t46, ptr %t49)
  %t51 = load ptr, ptr @ty-ptr, align 8
  %t52 = load ptr, ptr %tmp.addr.39, align 8
  %t53 = call ptr @alloc-val(ptr %t51, ptr %t52)
  ret ptr %t53
}

define ptr @emit-deref(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %p.addr.9 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %elem.addr.31 = alloca ptr, align 8
  %tmp.addr.37 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [20 x i8], ptr @.str.175, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %p.addr.9, align 8
  %t14 = load ptr, ptr %p.addr.9, align 8
  %t15 = getelementptr inbounds %Val, ptr %t14, i32 0, i32 0
  %t16 = load ptr, ptr %t15, align 8
  %t17 = getelementptr inbounds %Type, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp ne i32 %t18, 6
  store i1 %t19, ptr %or.val2, align 1
  br i1 %t19, label %or.end2, label %or.rhs2
or.rhs2:
  %t20 = load ptr, ptr %p.addr.9, align 8
  %t21 = getelementptr inbounds %Val, ptr %t20, i32 0, i32 0
  %t22 = load ptr, ptr %t21, align 8
  %t23 = getelementptr inbounds %Type, ptr %t22, i32 0, i32 5
  %t24 = load ptr, ptr %t23, align 8
  %t25 = icmp eq ptr %t24, null
  store i1 %t25, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t26 = load i1, ptr %or.val2, align 1
  br i1 %t26, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t27 = load ptr, ptr %cc.addr.0, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 1
  %t29 = load i32, ptr %t28, align 4
  %t30 = getelementptr inbounds [37 x i8], ptr @.str.176, i64 0, i64 0
  call void @die-at(i32 %t29, ptr %t30)
  br label %cond.end1
cond.end1:
  %t32 = load ptr, ptr %p.addr.9, align 8
  %t33 = getelementptr inbounds %Val, ptr %t32, i32 0, i32 0
  %t34 = load ptr, ptr %t33, align 8
  %t35 = getelementptr inbounds %Type, ptr %t34, i32 0, i32 5
  %t36 = load ptr, ptr %t35, align 8
  store ptr %t36, ptr %elem.addr.31, align 8
  %t38 = call ptr @new-tmp()
  store ptr %t38, ptr %tmp.addr.37, align 8
  %t39 = load ptr, ptr @g-body-stream, align 8
  %t40 = getelementptr inbounds [34 x i8], ptr @.str.177, i64 0, i64 0
  %t41 = load ptr, ptr %tmp.addr.37, align 8
  %t42 = load ptr, ptr %elem.addr.31, align 8
  %t43 = call ptr @type-to-ir(ptr %t42)
  %t44 = load ptr, ptr %p.addr.9, align 8
  %t45 = getelementptr inbounds %Val, ptr %t44, i32 0, i32 1
  %t46 = load ptr, ptr %t45, align 8
  %t47 = load ptr, ptr %elem.addr.31, align 8
  %t48 = call i32 @type-size(ptr %t47)
  %t49 = call i32 (ptr, ptr, ...) @fprintf(ptr %t39, ptr %t40, ptr %t41, ptr %t43, ptr %t46, i32 %t48)
  %t50 = load ptr, ptr %elem.addr.31, align 8
  %t51 = load ptr, ptr %tmp.addr.37, align 8
  %t52 = call ptr @alloc-val(ptr %t50, ptr %t51)
  ret ptr %t52
}

define ptr @emit-ptr-set(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %p.addr.9 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %elem.addr.31 = alloca ptr, align 8
  %v.addr.37 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 3
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [24 x i8], ptr @.str.178, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %p.addr.9, align 8
  %t14 = load ptr, ptr %p.addr.9, align 8
  %t15 = getelementptr inbounds %Val, ptr %t14, i32 0, i32 0
  %t16 = load ptr, ptr %t15, align 8
  %t17 = getelementptr inbounds %Type, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp ne i32 %t18, 6
  store i1 %t19, ptr %or.val2, align 1
  br i1 %t19, label %or.end2, label %or.rhs2
or.rhs2:
  %t20 = load ptr, ptr %p.addr.9, align 8
  %t21 = getelementptr inbounds %Val, ptr %t20, i32 0, i32 0
  %t22 = load ptr, ptr %t21, align 8
  %t23 = getelementptr inbounds %Type, ptr %t22, i32 0, i32 5
  %t24 = load ptr, ptr %t23, align 8
  %t25 = icmp eq ptr %t24, null
  store i1 %t25, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t26 = load i1, ptr %or.val2, align 1
  br i1 %t26, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t27 = load ptr, ptr %cc.addr.0, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 1
  %t29 = load i32, ptr %t28, align 4
  %t30 = getelementptr inbounds [40 x i8], ptr @.str.179, i64 0, i64 0
  call void @die-at(i32 %t29, ptr %t30)
  br label %cond.end1
cond.end1:
  %t32 = load ptr, ptr %p.addr.9, align 8
  %t33 = getelementptr inbounds %Val, ptr %t32, i32 0, i32 0
  %t34 = load ptr, ptr %t33, align 8
  %t35 = getelementptr inbounds %Type, ptr %t34, i32 0, i32 5
  %t36 = load ptr, ptr %t35, align 8
  store ptr %t36, ptr %elem.addr.31, align 8
  %t38 = load ptr, ptr %cc.addr.0, align 8
  %t39 = call ptr @node-at(ptr %t38, i32 2)
  %t40 = load ptr, ptr %scope.addr, align 8
  %t41 = call ptr @emit-node(ptr %t39, ptr %t40)
  store ptr %t41, ptr %v.addr.37, align 8
  %t42 = load ptr, ptr %v.addr.37, align 8
  %t43 = getelementptr inbounds %Val, ptr %t42, i32 0, i32 0
  %t44 = load ptr, ptr %t43, align 8
  %t45 = getelementptr inbounds %Type, ptr %t44, i32 0, i32 0
  %t46 = load i32, ptr %t45, align 4
  %t47 = load ptr, ptr %elem.addr.31, align 8
  %t48 = getelementptr inbounds %Type, ptr %t47, i32 0, i32 0
  %t49 = load i32, ptr %t48, align 4
  %t50 = icmp ne i32 %t46, %t49
  br i1 %t50, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t51 = load ptr, ptr %cc.addr.0, align 8
  %t52 = getelementptr inbounds %Node, ptr %t51, i32 0, i32 1
  %t53 = load i32, ptr %t52, align 4
  %t54 = getelementptr inbounds [30 x i8], ptr @.str.180, i64 0, i64 0
  call void @die-at(i32 %t53, ptr %t54)
  br label %cond.end3
cond.end3:
  %t55 = load ptr, ptr @g-body-stream, align 8
  %t56 = getelementptr inbounds [33 x i8], ptr @.str.181, i64 0, i64 0
  %t57 = load ptr, ptr %elem.addr.31, align 8
  %t58 = call ptr @type-to-ir(ptr %t57)
  %t59 = load ptr, ptr %v.addr.37, align 8
  %t60 = getelementptr inbounds %Val, ptr %t59, i32 0, i32 1
  %t61 = load ptr, ptr %t60, align 8
  %t62 = load ptr, ptr %p.addr.9, align 8
  %t63 = getelementptr inbounds %Val, ptr %t62, i32 0, i32 1
  %t64 = load ptr, ptr %t63, align 8
  %t65 = load ptr, ptr %elem.addr.31, align 8
  %t66 = call i32 @type-size(ptr %t65)
  %t67 = call i32 (ptr, ptr, ...) @fprintf(ptr %t55, ptr %t56, ptr %t58, ptr %t61, ptr %t64, i32 %t66)
  %t68 = load ptr, ptr @ty-void, align 8
  %t69 = call ptr @alloc-val(ptr %t68, ptr null)
  ret ptr %t69
}

define ptr @emit-ptr-add(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %p.addr.9 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %nv.addr.31 = alloca ptr, align 8
  %idx.addr.45 = alloca ptr, align 8
  %t.addr.55 = alloca ptr, align 8
  %elem.addr.69 = alloca ptr, align 8
  %tmp.addr.75 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 3
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [20 x i8], ptr @.str.182, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %p.addr.9, align 8
  %t14 = load ptr, ptr %p.addr.9, align 8
  %t15 = getelementptr inbounds %Val, ptr %t14, i32 0, i32 0
  %t16 = load ptr, ptr %t15, align 8
  %t17 = getelementptr inbounds %Type, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp ne i32 %t18, 6
  store i1 %t19, ptr %or.val2, align 1
  br i1 %t19, label %or.end2, label %or.rhs2
or.rhs2:
  %t20 = load ptr, ptr %p.addr.9, align 8
  %t21 = getelementptr inbounds %Val, ptr %t20, i32 0, i32 0
  %t22 = load ptr, ptr %t21, align 8
  %t23 = getelementptr inbounds %Type, ptr %t22, i32 0, i32 5
  %t24 = load ptr, ptr %t23, align 8
  %t25 = icmp eq ptr %t24, null
  store i1 %t25, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t26 = load i1, ptr %or.val2, align 1
  br i1 %t26, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t27 = load ptr, ptr %cc.addr.0, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 1
  %t29 = load i32, ptr %t28, align 4
  %t30 = getelementptr inbounds [36 x i8], ptr @.str.183, i64 0, i64 0
  call void @die-at(i32 %t29, ptr %t30)
  br label %cond.end1
cond.end1:
  %t32 = load ptr, ptr %cc.addr.0, align 8
  %t33 = call ptr @node-at(ptr %t32, i32 2)
  %t34 = load ptr, ptr %scope.addr, align 8
  %t35 = call ptr @emit-node(ptr %t33, ptr %t34)
  store ptr %t35, ptr %nv.addr.31, align 8
  %t36 = load ptr, ptr %nv.addr.31, align 8
  %t37 = getelementptr inbounds %Val, ptr %t36, i32 0, i32 0
  %t38 = load ptr, ptr %t37, align 8
  %t39 = call i32 @is-int-type(ptr %t38)
  %t40 = icmp eq i32 %t39, 0
  br i1 %t40, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t41 = load ptr, ptr %cc.addr.0, align 8
  %t42 = getelementptr inbounds %Node, ptr %t41, i32 0, i32 1
  %t43 = load i32, ptr %t42, align 4
  %t44 = getelementptr inbounds [29 x i8], ptr @.str.184, i64 0, i64 0
  call void @die-at(i32 %t43, ptr %t44)
  br label %cond.end3
cond.end3:
  %t46 = load ptr, ptr %nv.addr.31, align 8
  %t47 = getelementptr inbounds %Val, ptr %t46, i32 0, i32 1
  %t48 = load ptr, ptr %t47, align 8
  store ptr %t48, ptr %idx.addr.45, align 8
  %t49 = load ptr, ptr %nv.addr.31, align 8
  %t50 = getelementptr inbounds %Val, ptr %t49, i32 0, i32 0
  %t51 = load ptr, ptr %t50, align 8
  %t52 = getelementptr inbounds %Type, ptr %t51, i32 0, i32 0
  %t53 = load i32, ptr %t52, align 4
  %t54 = icmp ne i32 %t53, 5
  br i1 %t54, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t56 = call ptr @new-tmp()
  store ptr %t56, ptr %t.addr.55, align 8
  %t57 = load ptr, ptr @g-body-stream, align 8
  %t58 = getelementptr inbounds [26 x i8], ptr @.str.185, i64 0, i64 0
  %t59 = load ptr, ptr %t.addr.55, align 8
  %t60 = load ptr, ptr %nv.addr.31, align 8
  %t61 = getelementptr inbounds %Val, ptr %t60, i32 0, i32 0
  %t62 = load ptr, ptr %t61, align 8
  %t63 = call ptr @type-to-ir(ptr %t62)
  %t64 = load ptr, ptr %nv.addr.31, align 8
  %t65 = getelementptr inbounds %Val, ptr %t64, i32 0, i32 1
  %t66 = load ptr, ptr %t65, align 8
  %t67 = call i32 (ptr, ptr, ...) @fprintf(ptr %t57, ptr %t58, ptr %t59, ptr %t63, ptr %t66)
  %t68 = load ptr, ptr %t.addr.55, align 8
  store ptr %t68, ptr %idx.addr.45, align 8
  br label %cond.end4
cond.end4:
  %t70 = load ptr, ptr %p.addr.9, align 8
  %t71 = getelementptr inbounds %Val, ptr %t70, i32 0, i32 0
  %t72 = load ptr, ptr %t71, align 8
  %t73 = getelementptr inbounds %Type, ptr %t72, i32 0, i32 5
  %t74 = load ptr, ptr %t73, align 8
  store ptr %t74, ptr %elem.addr.69, align 8
  %t76 = call ptr @new-tmp()
  store ptr %t76, ptr %tmp.addr.75, align 8
  %t77 = load ptr, ptr @g-body-stream, align 8
  %t78 = getelementptr inbounds [50 x i8], ptr @.str.186, i64 0, i64 0
  %t79 = load ptr, ptr %tmp.addr.75, align 8
  %t80 = load ptr, ptr %elem.addr.69, align 8
  %t81 = call ptr @type-to-ir(ptr %t80)
  %t82 = load ptr, ptr %p.addr.9, align 8
  %t83 = getelementptr inbounds %Val, ptr %t82, i32 0, i32 1
  %t84 = load ptr, ptr %t83, align 8
  %t85 = load ptr, ptr %idx.addr.45, align 8
  %t86 = call i32 (ptr, ptr, ...) @fprintf(ptr %t77, ptr %t78, ptr %t79, ptr %t81, ptr %t84, ptr %t85)
  %t87 = load ptr, ptr %p.addr.9, align 8
  %t88 = getelementptr inbounds %Val, ptr %t87, i32 0, i32 0
  %t89 = load ptr, ptr %t88, align 8
  %t90 = load ptr, ptr %tmp.addr.75, align 8
  %t91 = call ptr @alloc-val(ptr %t89, ptr %t90)
  ret ptr %t91
}

define ptr @emit-not(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %a.addr.9 = alloca ptr, align 8
  %tmp.addr.24 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [18 x i8], ptr @.str.187, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %a.addr.9, align 8
  %t14 = load ptr, ptr %a.addr.9, align 8
  %t15 = getelementptr inbounds %Val, ptr %t14, i32 0, i32 0
  %t16 = load ptr, ptr %t15, align 8
  %t17 = getelementptr inbounds %Type, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp ne i32 %t18, 1
  br i1 %t19, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t20 = load ptr, ptr %cc.addr.0, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 1
  %t22 = load i32, ptr %t21, align 4
  %t23 = getelementptr inbounds [23 x i8], ptr @.str.188, i64 0, i64 0
  call void @die-at(i32 %t22, ptr %t23)
  br label %cond.end1
cond.end1:
  %t25 = call ptr @new-tmp()
  store ptr %t25, ptr %tmp.addr.24, align 8
  %t26 = load ptr, ptr @g-body-stream, align 8
  %t27 = getelementptr inbounds [21 x i8], ptr @.str.189, i64 0, i64 0
  %t28 = load ptr, ptr %tmp.addr.24, align 8
  %t29 = load ptr, ptr %a.addr.9, align 8
  %t30 = getelementptr inbounds %Val, ptr %t29, i32 0, i32 1
  %t31 = load ptr, ptr %t30, align 8
  %t32 = call i32 (ptr, ptr, ...) @fprintf(ptr %t26, ptr %t27, ptr %t28, ptr %t31)
  %t33 = load ptr, ptr @ty-i1, align 8
  %t34 = load ptr, ptr %tmp.addr.24, align 8
  %t35 = call ptr @alloc-val(ptr %t33, ptr %t34)
  ret ptr %t35
}

define ptr @emit-short-circuit(ptr %call.arg, ptr %scope.arg, i32 %is-and.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %is-and.addr = alloca i32, align 4
  store i32 %is-and.arg, ptr %is-and.addr, align 4
  %cc.addr.0 = alloca ptr, align 8
  %tag.addr.2 = alloca ptr, align 8
  %id.addr.16 = alloca i32, align 4
  %rhs-lbl.addr.18 = alloca ptr, align 8
  %end-lbl.addr.23 = alloca ptr, align 8
  %slot.addr.28 = alloca ptr, align 8
  %lhs.addr.37 = alloca ptr, align 8
  %rhs.addr.84 = alloca ptr, align 8
  %tmp.addr.117 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t3 = getelementptr inbounds [3 x i8], ptr @.str.190, i64 0, i64 0
  store ptr %t3, ptr %tag.addr.2, align 8
  %t4 = load i32, ptr %is-and.addr, align 4
  %t5 = icmp ne i32 %t4, 0
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t6 = getelementptr inbounds [4 x i8], ptr @.str.191, i64 0, i64 0
  store ptr %t6, ptr %tag.addr.2, align 8
  br label %cond.end0
cond.end0:
  %t7 = load ptr, ptr %cc.addr.0, align 8
  %t8 = call i32 @node-len(ptr %t7)
  %t9 = icmp ne i32 %t8, 3
  br i1 %t9, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = getelementptr inbounds %Node, ptr %t10, i32 0, i32 1
  %t12 = load i32, ptr %t11, align 4
  %t13 = getelementptr inbounds [18 x i8], ptr @.str.192, i64 0, i64 0
  %t14 = load ptr, ptr %tag.addr.2, align 8
  %t15 = call ptr @fmt-s(ptr %t13, ptr %t14)
  call void @die-at(i32 %t12, ptr %t15)
  br label %cond.end1
cond.end1:
  %t17 = call i32 @new-label-id()
  store i32 %t17, ptr %id.addr.16, align 4
  %t19 = getelementptr inbounds [9 x i8], ptr @.str.193, i64 0, i64 0
  %t20 = load ptr, ptr %tag.addr.2, align 8
  %t21 = load i32, ptr %id.addr.16, align 4
  %t22 = call ptr @fmt-sd(ptr %t19, ptr %t20, i32 %t21)
  store ptr %t22, ptr %rhs-lbl.addr.18, align 8
  %t24 = getelementptr inbounds [9 x i8], ptr @.str.194, i64 0, i64 0
  %t25 = load ptr, ptr %tag.addr.2, align 8
  %t26 = load i32, ptr %id.addr.16, align 4
  %t27 = call ptr @fmt-sd(ptr %t24, ptr %t25, i32 %t26)
  store ptr %t27, ptr %end-lbl.addr.23, align 8
  %t29 = getelementptr inbounds [11 x i8], ptr @.str.195, i64 0, i64 0
  %t30 = load ptr, ptr %tag.addr.2, align 8
  %t31 = load i32, ptr %id.addr.16, align 4
  %t32 = call ptr @fmt-sd(ptr %t29, ptr %t30, i32 %t31)
  store ptr %t32, ptr %slot.addr.28, align 8
  %t33 = load ptr, ptr @g-entry-stream, align 8
  %t34 = getelementptr inbounds [27 x i8], ptr @.str.196, i64 0, i64 0
  %t35 = load ptr, ptr %slot.addr.28, align 8
  %t36 = call i32 (ptr, ptr, ...) @fprintf(ptr %t33, ptr %t34, ptr %t35)
  %t38 = load ptr, ptr %cc.addr.0, align 8
  %t39 = call ptr @node-at(ptr %t38, i32 1)
  %t40 = load ptr, ptr %scope.addr, align 8
  %t41 = call ptr @emit-node(ptr %t39, ptr %t40)
  store ptr %t41, ptr %lhs.addr.37, align 8
  %t42 = load ptr, ptr %lhs.addr.37, align 8
  %t43 = getelementptr inbounds %Val, ptr %t42, i32 0, i32 0
  %t44 = load ptr, ptr %t43, align 8
  %t45 = getelementptr inbounds %Type, ptr %t44, i32 0, i32 0
  %t46 = load i32, ptr %t45, align 4
  %t47 = icmp ne i32 %t46, 1
  br i1 %t47, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t48 = load ptr, ptr %cc.addr.0, align 8
  %t49 = call ptr @node-at(ptr %t48, i32 1)
  %t50 = getelementptr inbounds %Node, ptr %t49, i32 0, i32 1
  %t51 = load i32, ptr %t50, align 4
  %t52 = getelementptr inbounds [23 x i8], ptr @.str.197, i64 0, i64 0
  %t53 = load ptr, ptr %tag.addr.2, align 8
  %t54 = call ptr @fmt-s(ptr %t52, ptr %t53)
  call void @die-at(i32 %t51, ptr %t54)
  br label %cond.end2
cond.end2:
  %t55 = load ptr, ptr @g-body-stream, align 8
  %t56 = getelementptr inbounds [32 x i8], ptr @.str.198, i64 0, i64 0
  %t57 = load ptr, ptr %lhs.addr.37, align 8
  %t58 = getelementptr inbounds %Val, ptr %t57, i32 0, i32 1
  %t59 = load ptr, ptr %t58, align 8
  %t60 = load ptr, ptr %slot.addr.28, align 8
  %t61 = call i32 (ptr, ptr, ...) @fprintf(ptr %t55, ptr %t56, ptr %t59, ptr %t60)
  %t62 = load i32, ptr %is-and.addr, align 4
  %t63 = icmp ne i32 %t62, 0
  br i1 %t63, label %cond.then3.0, label %cond.test3.1
cond.then3.0:
  %t64 = load ptr, ptr @g-body-stream, align 8
  %t65 = getelementptr inbounds [36 x i8], ptr @.str.199, i64 0, i64 0
  %t66 = load ptr, ptr %lhs.addr.37, align 8
  %t67 = getelementptr inbounds %Val, ptr %t66, i32 0, i32 1
  %t68 = load ptr, ptr %t67, align 8
  %t69 = load ptr, ptr %rhs-lbl.addr.18, align 8
  %t70 = load ptr, ptr %end-lbl.addr.23, align 8
  %t71 = call i32 (ptr, ptr, ...) @fprintf(ptr %t64, ptr %t65, ptr %t68, ptr %t69, ptr %t70)
  br label %cond.end3
cond.test3.1:
  br i1 1, label %cond.then3.1, label %cond.end3
cond.then3.1:
  %t72 = load ptr, ptr @g-body-stream, align 8
  %t73 = getelementptr inbounds [36 x i8], ptr @.str.200, i64 0, i64 0
  %t74 = load ptr, ptr %lhs.addr.37, align 8
  %t75 = getelementptr inbounds %Val, ptr %t74, i32 0, i32 1
  %t76 = load ptr, ptr %t75, align 8
  %t77 = load ptr, ptr %end-lbl.addr.23, align 8
  %t78 = load ptr, ptr %rhs-lbl.addr.18, align 8
  %t79 = call i32 (ptr, ptr, ...) @fprintf(ptr %t72, ptr %t73, ptr %t76, ptr %t77, ptr %t78)
  br label %cond.end3
cond.end3:
  %t80 = load ptr, ptr @g-body-stream, align 8
  %t81 = getelementptr inbounds [5 x i8], ptr @.str.201, i64 0, i64 0
  %t82 = load ptr, ptr %rhs-lbl.addr.18, align 8
  %t83 = call i32 (ptr, ptr, ...) @fprintf(ptr %t80, ptr %t81, ptr %t82)
  store i32 0, ptr @g-block-term, align 4
  %t85 = load ptr, ptr %cc.addr.0, align 8
  %t86 = call ptr @node-at(ptr %t85, i32 2)
  %t87 = load ptr, ptr %scope.addr, align 8
  %t88 = call ptr @emit-node(ptr %t86, ptr %t87)
  store ptr %t88, ptr %rhs.addr.84, align 8
  %t89 = load ptr, ptr %rhs.addr.84, align 8
  %t90 = getelementptr inbounds %Val, ptr %t89, i32 0, i32 0
  %t91 = load ptr, ptr %t90, align 8
  %t92 = getelementptr inbounds %Type, ptr %t91, i32 0, i32 0
  %t93 = load i32, ptr %t92, align 4
  %t94 = icmp ne i32 %t93, 1
  br i1 %t94, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t95 = load ptr, ptr %cc.addr.0, align 8
  %t96 = call ptr @node-at(ptr %t95, i32 2)
  %t97 = getelementptr inbounds %Node, ptr %t96, i32 0, i32 1
  %t98 = load i32, ptr %t97, align 4
  %t99 = getelementptr inbounds [23 x i8], ptr @.str.202, i64 0, i64 0
  %t100 = load ptr, ptr %tag.addr.2, align 8
  %t101 = call ptr @fmt-s(ptr %t99, ptr %t100)
  call void @die-at(i32 %t98, ptr %t101)
  br label %cond.end4
cond.end4:
  %t102 = load ptr, ptr @g-body-stream, align 8
  %t103 = getelementptr inbounds [32 x i8], ptr @.str.203, i64 0, i64 0
  %t104 = load ptr, ptr %rhs.addr.84, align 8
  %t105 = getelementptr inbounds %Val, ptr %t104, i32 0, i32 1
  %t106 = load ptr, ptr %t105, align 8
  %t107 = load ptr, ptr %slot.addr.28, align 8
  %t108 = call i32 (ptr, ptr, ...) @fprintf(ptr %t102, ptr %t103, ptr %t106, ptr %t107)
  %t109 = load ptr, ptr @g-body-stream, align 8
  %t110 = getelementptr inbounds [17 x i8], ptr @.str.204, i64 0, i64 0
  %t111 = load ptr, ptr %end-lbl.addr.23, align 8
  %t112 = call i32 (ptr, ptr, ...) @fprintf(ptr %t109, ptr %t110, ptr %t111)
  %t113 = load ptr, ptr @g-body-stream, align 8
  %t114 = getelementptr inbounds [5 x i8], ptr @.str.205, i64 0, i64 0
  %t115 = load ptr, ptr %end-lbl.addr.23, align 8
  %t116 = call i32 (ptr, ptr, ...) @fprintf(ptr %t113, ptr %t114, ptr %t115)
  store i32 0, ptr @g-block-term, align 4
  %t118 = call ptr @new-tmp()
  store ptr %t118, ptr %tmp.addr.117, align 8
  %t119 = load ptr, ptr @g-body-stream, align 8
  %t120 = getelementptr inbounds [33 x i8], ptr @.str.206, i64 0, i64 0
  %t121 = load ptr, ptr %tmp.addr.117, align 8
  %t122 = load ptr, ptr %slot.addr.28, align 8
  %t123 = call i32 (ptr, ptr, ...) @fprintf(ptr %t119, ptr %t120, ptr %t121, ptr %t122)
  %t124 = load ptr, ptr @ty-i1, align 8
  %t125 = load ptr, ptr %tmp.addr.117, align 8
  %t126 = call ptr @alloc-val(ptr %t124, ptr %t125)
  ret ptr %t126
}

define ptr @emit-call(ptr %call.arg, ptr %scope.arg, ptr %sym.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %sym.addr = alloca ptr, align 8
  store ptr %sym.arg, ptr %sym.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %ss.addr.2 = alloca ptr, align 8
  %nargs.addr.4 = alloca i32, align 4
  %args.addr.8 = alloca ptr, align 8
  %i.addr.15 = alloca i32, align 4
  %v.addr.19 = alloca ptr, align 8
  %arglist.addr.36 = alloca ptr, align 8
  %apos.addr.38 = alloca i64, align 8
  %av.addr.47 = alloca ptr, align 8
  %sep.addr.52 = alloca ptr, align 8
  %w.addr.57 = alloca i32, align 4
  %ft.addr.80 = alloca ptr, align 8
  %sig.addr.100 = alloca ptr, align 8
  %sp.addr.102 = alloca i64, align 8
  %w.addr.104 = alloca i32, align 4
  %pt.addr.120 = alloca ptr, align 8
  %sep.addr.128 = alloca ptr, align 8
  %va-sep.addr.150 = alloca ptr, align 8
  %tmp.addr.180 = alloca ptr, align 8
  %tmp.addr.213 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t3 = load ptr, ptr %sym.addr, align 8
  store ptr %t3, ptr %ss.addr.2, align 8
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = call i32 @node-len(ptr %t5)
  %t7 = sub nsw i32 %t6, 1
  store i32 %t7, ptr %nargs.addr.4, align 4
  %t9 = load i32, ptr %nargs.addr.4, align 4
  %t10 = call i64 @i64(i32 %t9)
  %t11 = getelementptr %Val, ptr null, i32 1
  %t12 = ptrtoint ptr %t11 to i64
  %t13 = mul nsw i64 %t10, %t12
  %t14 = call ptr @arena-alloc(i64 %t13)
  store ptr %t14, ptr %args.addr.8, align 8
  store i32 0, ptr %i.addr.15, align 4
  br label %while.cond0
while.cond0:
  %t16 = load i32, ptr %i.addr.15, align 4
  %t17 = load i32, ptr %nargs.addr.4, align 4
  %t18 = icmp slt i32 %t16, %t17
  br i1 %t18, label %while.body0, label %while.end0
while.body0:
  %t20 = load ptr, ptr %cc.addr.0, align 8
  %t21 = load i32, ptr %i.addr.15, align 4
  %t22 = add nsw i32 %t21, 1
  %t23 = call ptr @node-at(ptr %t20, i32 %t22)
  %t24 = load ptr, ptr %scope.addr, align 8
  %t25 = call ptr @emit-node(ptr %t23, ptr %t24)
  store ptr %t25, ptr %v.addr.19, align 8
  %t26 = load ptr, ptr %args.addr.8, align 8
  %t27 = load i32, ptr %i.addr.15, align 4
  %t28 = sext i32 %t27 to i64
  %t29 = getelementptr inbounds %Val, ptr %t26, i64 %t28
  %t30 = load ptr, ptr %v.addr.19, align 8
  %t31 = getelementptr %Val, ptr null, i32 1
  %t32 = ptrtoint ptr %t31 to i64
  %t33 = call ptr @memcpy(ptr %t29, ptr %t30, i64 %t32)
  %t34 = load i32, ptr %i.addr.15, align 4
  %t35 = add nsw i32 %t34, 1
  store i32 %t35, ptr %i.addr.15, align 4
  br label %while.cond0
while.end0:
  %t37 = alloca i8, i32 2048, align 1
  store ptr %t37, ptr %arglist.addr.36, align 8
  %t39 = sext i32 0 to i64
  store i64 %t39, ptr %apos.addr.38, align 8
  %t40 = load ptr, ptr %arglist.addr.36, align 8
  %t41 = sext i32 0 to i64
  %t42 = trunc i32 0 to i8
  %t43 = getelementptr inbounds i8, ptr %t40, i64 %t41
  store i8 %t42, ptr %t43, align 1
  store i32 0, ptr %i.addr.15, align 4
  br label %while.cond1
while.cond1:
  %t44 = load i32, ptr %i.addr.15, align 4
  %t45 = load i32, ptr %nargs.addr.4, align 4
  %t46 = icmp slt i32 %t44, %t45
  br i1 %t46, label %while.body1, label %while.end1
while.body1:
  %t48 = load ptr, ptr %args.addr.8, align 8
  %t49 = load i32, ptr %i.addr.15, align 4
  %t50 = sext i32 %t49 to i64
  %t51 = getelementptr inbounds %Val, ptr %t48, i64 %t50
  store ptr %t51, ptr %av.addr.47, align 8
  %t53 = getelementptr inbounds [1 x i8], ptr @.str.207, i64 0, i64 0
  store ptr %t53, ptr %sep.addr.52, align 8
  %t54 = load i32, ptr %i.addr.15, align 4
  %t55 = icmp ne i32 %t54, 0
  br i1 %t55, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t56 = getelementptr inbounds [3 x i8], ptr @.str.208, i64 0, i64 0
  store ptr %t56, ptr %sep.addr.52, align 8
  br label %cond.end2
cond.end2:
  %t58 = load ptr, ptr %arglist.addr.36, align 8
  %t59 = load i64, ptr %apos.addr.38, align 8
  %t60 = getelementptr inbounds i8, ptr %t58, i64 %t59
  %t61 = sext i32 2048 to i64
  %t62 = load i64, ptr %apos.addr.38, align 8
  %t63 = sub nsw i64 %t61, %t62
  %t64 = getelementptr inbounds [8 x i8], ptr @.str.209, i64 0, i64 0
  %t65 = load ptr, ptr %sep.addr.52, align 8
  %t66 = load ptr, ptr %av.addr.47, align 8
  %t67 = getelementptr inbounds %Val, ptr %t66, i32 0, i32 0
  %t68 = load ptr, ptr %t67, align 8
  %t69 = call ptr @type-to-ir(ptr %t68)
  %t70 = load ptr, ptr %av.addr.47, align 8
  %t71 = getelementptr inbounds %Val, ptr %t70, i32 0, i32 1
  %t72 = load ptr, ptr %t71, align 8
  %t73 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t60, i64 %t63, ptr %t64, ptr %t65, ptr %t69, ptr %t72)
  store i32 %t73, ptr %w.addr.57, align 4
  %t74 = load i64, ptr %apos.addr.38, align 8
  %t75 = load i32, ptr %w.addr.57, align 4
  %t76 = call i64 @i64(i32 %t75)
  %t77 = add nsw i64 %t74, %t76
  store i64 %t77, ptr %apos.addr.38, align 8
  %t78 = load i32, ptr %i.addr.15, align 4
  %t79 = add nsw i32 %t78, 1
  store i32 %t79, ptr %i.addr.15, align 4
  br label %while.cond1
while.end1:
  %t81 = load ptr, ptr %ss.addr.2, align 8
  %t82 = getelementptr inbounds %Sym, ptr %t81, i32 0, i32 1
  %t83 = load ptr, ptr %t82, align 8
  store ptr %t83, ptr %ft.addr.80, align 8
  %t84 = load ptr, ptr %ft.addr.80, align 8
  %t85 = getelementptr inbounds %Type, ptr %t84, i32 0, i32 0
  %t86 = load i32, ptr %t85, align 4
  %t87 = icmp ne i32 %t86, 7
  br i1 %t87, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t88 = load ptr, ptr %cc.addr.0, align 8
  %t89 = getelementptr inbounds %Node, ptr %t88, i32 0, i32 1
  %t90 = load i32, ptr %t89, align 4
  %t91 = getelementptr inbounds [19 x i8], ptr @.str.210, i64 0, i64 0
  %t92 = load ptr, ptr %ss.addr.2, align 8
  %t93 = getelementptr inbounds %Sym, ptr %t92, i32 0, i32 0
  %t94 = load ptr, ptr %t93, align 8
  %t95 = call ptr @fmt-s(ptr %t91, ptr %t94)
  call void @die-at(i32 %t90, ptr %t95)
  br label %cond.end3
cond.end3:
  %t96 = load ptr, ptr %ft.addr.80, align 8
  %t97 = getelementptr inbounds %Type, ptr %t96, i32 0, i32 4
  %t98 = load i32, ptr %t97, align 4
  %t99 = icmp ne i32 %t98, 0
  br i1 %t99, label %cond.then4.0, label %cond.test4.1
cond.then4.0:
  %t101 = alloca i8, i32 512, align 1
  store ptr %t101, ptr %sig.addr.100, align 8
  %t103 = sext i32 0 to i64
  store i64 %t103, ptr %sp.addr.102, align 8
  %t105 = load ptr, ptr %sig.addr.100, align 8
  %t106 = sext i32 512 to i64
  %t107 = getelementptr inbounds [5 x i8], ptr @.str.211, i64 0, i64 0
  %t108 = load ptr, ptr %ft.addr.80, align 8
  %t109 = getelementptr inbounds %Type, ptr %t108, i32 0, i32 1
  %t110 = load ptr, ptr %t109, align 8
  %t111 = call ptr @type-to-ir(ptr %t110)
  %t112 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t105, i64 %t106, ptr %t107, ptr %t111)
  store i32 %t112, ptr %w.addr.104, align 4
  %t113 = load i32, ptr %w.addr.104, align 4
  %t114 = call i64 @i64(i32 %t113)
  store i64 %t114, ptr %sp.addr.102, align 8
  store i32 0, ptr %i.addr.15, align 4
  br label %while.cond5
while.cond5:
  %t115 = load i32, ptr %i.addr.15, align 4
  %t116 = load ptr, ptr %ft.addr.80, align 8
  %t117 = getelementptr inbounds %Type, ptr %t116, i32 0, i32 3
  %t118 = load i32, ptr %t117, align 4
  %t119 = icmp slt i32 %t115, %t118
  br i1 %t119, label %while.body5, label %while.end5
while.body5:
  %t121 = load ptr, ptr %ft.addr.80, align 8
  %t122 = getelementptr inbounds %Type, ptr %t121, i32 0, i32 2
  %t123 = load ptr, ptr %t122, align 8
  %t124 = load i32, ptr %i.addr.15, align 4
  %t125 = sext i32 %t124 to i64
  %t126 = getelementptr inbounds ptr, ptr %t123, i64 %t125
  %t127 = load ptr, ptr %t126, align 8
  store ptr %t127, ptr %pt.addr.120, align 8
  %t129 = getelementptr inbounds [1 x i8], ptr @.str.212, i64 0, i64 0
  store ptr %t129, ptr %sep.addr.128, align 8
  %t130 = load i32, ptr %i.addr.15, align 4
  %t131 = icmp ne i32 %t130, 0
  br i1 %t131, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t132 = getelementptr inbounds [3 x i8], ptr @.str.213, i64 0, i64 0
  store ptr %t132, ptr %sep.addr.128, align 8
  br label %cond.end6
cond.end6:
  %t133 = load ptr, ptr %sig.addr.100, align 8
  %t134 = load i64, ptr %sp.addr.102, align 8
  %t135 = getelementptr inbounds i8, ptr %t133, i64 %t134
  %t136 = sext i32 512 to i64
  %t137 = load i64, ptr %sp.addr.102, align 8
  %t138 = sub nsw i64 %t136, %t137
  %t139 = getelementptr inbounds [5 x i8], ptr @.str.214, i64 0, i64 0
  %t140 = load ptr, ptr %sep.addr.128, align 8
  %t141 = load ptr, ptr %pt.addr.120, align 8
  %t142 = call ptr @type-to-ir(ptr %t141)
  %t143 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t135, i64 %t138, ptr %t139, ptr %t140, ptr %t142)
  store i32 %t143, ptr %w.addr.104, align 4
  %t144 = load i64, ptr %sp.addr.102, align 8
  %t145 = load i32, ptr %w.addr.104, align 4
  %t146 = call i64 @i64(i32 %t145)
  %t147 = add nsw i64 %t144, %t146
  store i64 %t147, ptr %sp.addr.102, align 8
  %t148 = load i32, ptr %i.addr.15, align 4
  %t149 = add nsw i32 %t148, 1
  store i32 %t149, ptr %i.addr.15, align 4
  br label %while.cond5
while.end5:
  %t151 = getelementptr inbounds [1 x i8], ptr @.str.215, i64 0, i64 0
  store ptr %t151, ptr %va-sep.addr.150, align 8
  %t152 = load ptr, ptr %ft.addr.80, align 8
  %t153 = getelementptr inbounds %Type, ptr %t152, i32 0, i32 3
  %t154 = load i32, ptr %t153, align 4
  %t155 = icmp ne i32 %t154, 0
  br i1 %t155, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t156 = getelementptr inbounds [3 x i8], ptr @.str.216, i64 0, i64 0
  store ptr %t156, ptr %va-sep.addr.150, align 8
  br label %cond.end7
cond.end7:
  %t157 = load ptr, ptr %sig.addr.100, align 8
  %t158 = load i64, ptr %sp.addr.102, align 8
  %t159 = getelementptr inbounds i8, ptr %t157, i64 %t158
  %t160 = sext i32 512 to i64
  %t161 = load i64, ptr %sp.addr.102, align 8
  %t162 = sub nsw i64 %t160, %t161
  %t163 = getelementptr inbounds [7 x i8], ptr @.str.217, i64 0, i64 0
  %t164 = load ptr, ptr %va-sep.addr.150, align 8
  %t165 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t159, i64 %t162, ptr %t163, ptr %t164)
  %t166 = load ptr, ptr %ft.addr.80, align 8
  %t167 = getelementptr inbounds %Type, ptr %t166, i32 0, i32 1
  %t168 = load ptr, ptr %t167, align 8
  %t169 = getelementptr inbounds %Type, ptr %t168, i32 0, i32 0
  %t170 = load i32, ptr %t169, align 4
  %t171 = icmp eq i32 %t170, 0
  br i1 %t171, label %cond.then8.0, label %cond.test8.1
cond.then8.0:
  %t172 = load ptr, ptr @g-body-stream, align 8
  %t173 = getelementptr inbounds [18 x i8], ptr @.str.218, i64 0, i64 0
  %t174 = load ptr, ptr %sig.addr.100, align 8
  %t175 = load ptr, ptr %ss.addr.2, align 8
  %t176 = getelementptr inbounds %Sym, ptr %t175, i32 0, i32 2
  %t177 = load ptr, ptr %t176, align 8
  %t178 = load ptr, ptr %arglist.addr.36, align 8
  %t179 = call i32 (ptr, ptr, ...) @fprintf(ptr %t172, ptr %t173, ptr %t174, ptr %t177, ptr %t178)
  br label %cond.end8
cond.test8.1:
  br i1 1, label %cond.then8.1, label %cond.end8
cond.then8.1:
  %t181 = call ptr @new-tmp()
  store ptr %t181, ptr %tmp.addr.180, align 8
  %t182 = load ptr, ptr @g-body-stream, align 8
  %t183 = getelementptr inbounds [23 x i8], ptr @.str.219, i64 0, i64 0
  %t184 = load ptr, ptr %tmp.addr.180, align 8
  %t185 = load ptr, ptr %sig.addr.100, align 8
  %t186 = load ptr, ptr %ss.addr.2, align 8
  %t187 = getelementptr inbounds %Sym, ptr %t186, i32 0, i32 2
  %t188 = load ptr, ptr %t187, align 8
  %t189 = load ptr, ptr %arglist.addr.36, align 8
  %t190 = call i32 (ptr, ptr, ...) @fprintf(ptr %t182, ptr %t183, ptr %t184, ptr %t185, ptr %t188, ptr %t189)
  %t191 = load ptr, ptr %ft.addr.80, align 8
  %t192 = getelementptr inbounds %Type, ptr %t191, i32 0, i32 1
  %t193 = load ptr, ptr %t192, align 8
  %t194 = load ptr, ptr %tmp.addr.180, align 8
  %t195 = call ptr @alloc-val(ptr %t193, ptr %t194)
  ret ptr %t195
cond.end8:
  br label %cond.end4
cond.test4.1:
  br i1 1, label %cond.then4.1, label %cond.end4
cond.then4.1:
  %t196 = load ptr, ptr %ft.addr.80, align 8
  %t197 = getelementptr inbounds %Type, ptr %t196, i32 0, i32 1
  %t198 = load ptr, ptr %t197, align 8
  %t199 = getelementptr inbounds %Type, ptr %t198, i32 0, i32 0
  %t200 = load i32, ptr %t199, align 4
  %t201 = icmp eq i32 %t200, 0
  br i1 %t201, label %cond.then9.0, label %cond.test9.1
cond.then9.0:
  %t202 = load ptr, ptr @g-body-stream, align 8
  %t203 = getelementptr inbounds [18 x i8], ptr @.str.220, i64 0, i64 0
  %t204 = load ptr, ptr %ft.addr.80, align 8
  %t205 = getelementptr inbounds %Type, ptr %t204, i32 0, i32 1
  %t206 = load ptr, ptr %t205, align 8
  %t207 = call ptr @type-to-ir(ptr %t206)
  %t208 = load ptr, ptr %ss.addr.2, align 8
  %t209 = getelementptr inbounds %Sym, ptr %t208, i32 0, i32 2
  %t210 = load ptr, ptr %t209, align 8
  %t211 = load ptr, ptr %arglist.addr.36, align 8
  %t212 = call i32 (ptr, ptr, ...) @fprintf(ptr %t202, ptr %t203, ptr %t207, ptr %t210, ptr %t211)
  br label %cond.end9
cond.test9.1:
  br i1 1, label %cond.then9.1, label %cond.end9
cond.then9.1:
  %t214 = call ptr @new-tmp()
  store ptr %t214, ptr %tmp.addr.213, align 8
  %t215 = load ptr, ptr @g-body-stream, align 8
  %t216 = getelementptr inbounds [23 x i8], ptr @.str.221, i64 0, i64 0
  %t217 = load ptr, ptr %tmp.addr.213, align 8
  %t218 = load ptr, ptr %ft.addr.80, align 8
  %t219 = getelementptr inbounds %Type, ptr %t218, i32 0, i32 1
  %t220 = load ptr, ptr %t219, align 8
  %t221 = call ptr @type-to-ir(ptr %t220)
  %t222 = load ptr, ptr %ss.addr.2, align 8
  %t223 = getelementptr inbounds %Sym, ptr %t222, i32 0, i32 2
  %t224 = load ptr, ptr %t223, align 8
  %t225 = load ptr, ptr %arglist.addr.36, align 8
  %t226 = call i32 (ptr, ptr, ...) @fprintf(ptr %t215, ptr %t216, ptr %t217, ptr %t221, ptr %t224, ptr %t225)
  %t227 = load ptr, ptr %ft.addr.80, align 8
  %t228 = getelementptr inbounds %Type, ptr %t227, i32 0, i32 1
  %t229 = load ptr, ptr %t228, align 8
  %t230 = load ptr, ptr %tmp.addr.213, align 8
  %t231 = call ptr @alloc-val(ptr %t229, ptr %t230)
  ret ptr %t231
cond.end9:
  br label %cond.end4
cond.end4:
  %t232 = load ptr, ptr @ty-void, align 8
  %t233 = call ptr @alloc-val(ptr %t232, ptr null)
  ret ptr %t233
}

define ptr @emit-return(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %v.addr.17 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp eq i32 %t3, 1
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr @g-body-stream, align 8
  %t6 = getelementptr inbounds [12 x i8], ptr @.str.222, i64 0, i64 0
  %t7 = call i32 (ptr, ptr, ...) @fprintf(ptr %t5, ptr %t6)
  store i32 1, ptr @g-block-term, align 4
  %t8 = load ptr, ptr @ty-void, align 8
  %t9 = call ptr @alloc-val(ptr %t8, ptr null)
  ret ptr %t9
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call i32 @node-len(ptr %t10)
  %t12 = icmp ne i32 %t11, 2
  br i1 %t12, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t13 = load ptr, ptr %cc.addr.0, align 8
  %t14 = getelementptr inbounds %Node, ptr %t13, i32 0, i32 1
  %t15 = load i32, ptr %t14, align 4
  %t16 = getelementptr inbounds [27 x i8], ptr @.str.223, i64 0, i64 0
  call void @die-at(i32 %t15, ptr %t16)
  br label %cond.end1
cond.end1:
  %t18 = load ptr, ptr %cc.addr.0, align 8
  %t19 = call ptr @node-at(ptr %t18, i32 1)
  %t20 = load ptr, ptr %scope.addr, align 8
  %t21 = call ptr @emit-node(ptr %t19, ptr %t20)
  store ptr %t21, ptr %v.addr.17, align 8
  %t22 = load ptr, ptr @g-body-stream, align 8
  %t23 = getelementptr inbounds [13 x i8], ptr @.str.224, i64 0, i64 0
  %t24 = load ptr, ptr %v.addr.17, align 8
  %t25 = getelementptr inbounds %Val, ptr %t24, i32 0, i32 0
  %t26 = load ptr, ptr %t25, align 8
  %t27 = call ptr @type-to-ir(ptr %t26)
  %t28 = load ptr, ptr %v.addr.17, align 8
  %t29 = getelementptr inbounds %Val, ptr %t28, i32 0, i32 1
  %t30 = load ptr, ptr %t29, align 8
  %t31 = call i32 (ptr, ptr, ...) @fprintf(ptr %t22, ptr %t23, ptr %t27, ptr %t30)
  store i32 1, ptr @g-block-term, align 4
  %t32 = load ptr, ptr @ty-void, align 8
  %t33 = call ptr @alloc-val(ptr %t32, ptr null)
  ret ptr %t33
}

define ptr @emit-do(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %last.addr.2 = alloca ptr, align 8
  %i.addr.5 = alloca i32, align 4
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t3 = load ptr, ptr @ty-void, align 8
  %t4 = call ptr @alloc-val(ptr %t3, ptr null)
  store ptr %t4, ptr %last.addr.2, align 8
  store i32 1, ptr %i.addr.5, align 4
  br label %while.cond0
while.cond0:
  %t6 = load i32, ptr %i.addr.5, align 4
  %t7 = load ptr, ptr %cc.addr.0, align 8
  %t8 = call i32 @node-len(ptr %t7)
  %t9 = icmp slt i32 %t6, %t8
  br i1 %t9, label %while.body0, label %while.end0
while.body0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = load i32, ptr %i.addr.5, align 4
  %t12 = call ptr @node-at(ptr %t10, i32 %t11)
  %t13 = load ptr, ptr %scope.addr, align 8
  %t14 = call ptr @emit-node(ptr %t12, ptr %t13)
  store ptr %t14, ptr %last.addr.2, align 8
  %t15 = load i32, ptr %i.addr.5, align 4
  %t16 = add nsw i32 %t15, 1
  store i32 %t16, ptr %i.addr.5, align 4
  br label %while.cond0
while.end0:
  %t17 = load ptr, ptr %last.addr.2, align 8
  ret ptr %t17
}

define ptr @emit-let(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %or.val1 = alloca i1, align 1
  %binds.addr.15 = alloca ptr, align 8
  %inner.addr.26 = alloca ptr, align 8
  %i.addr.29 = alloca i32, align 4
  %bname.addr.34 = alloca ptr, align 8
  %bval-node.addr.38 = alloca ptr, align 8
  %name.addr.51 = alloca ptr, align 8
  %type-name.addr.52 = alloca ptr, align 8
  %ty.addr.64 = alloca ptr, align 8
  %slot.addr.70 = alloca ptr, align 8
  %align.addr.75 = alloca i32, align 4
  %v.addr.87 = alloca ptr, align 8
  %last.addr.123 = alloca ptr, align 8
  %j.addr.126 = alloca i32, align 4
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp slt i32 %t3, 2
  store i1 %t4, ptr %or.val1, align 1
  br i1 %t4, label %or.end1, label %or.rhs1
or.rhs1:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = call ptr @node-at(ptr %t5, i32 1)
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 0
  %t8 = load i32, ptr %t7, align 4
  %t9 = icmp ne i32 %t8, 3
  store i1 %t9, ptr %or.val1, align 1
  br label %or.end1
or.end1:
  %t10 = load i1, ptr %or.val1, align 1
  br i1 %t10, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t11 = load ptr, ptr %cc.addr.0, align 8
  %t12 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 1
  %t13 = load i32, ptr %t12, align 4
  %t14 = getelementptr inbounds [14 x i8], ptr @.str.225, i64 0, i64 0
  call void @die-at(i32 %t13, ptr %t14)
  br label %cond.end0
cond.end0:
  %t16 = load ptr, ptr %cc.addr.0, align 8
  %t17 = call ptr @node-at(ptr %t16, i32 1)
  store ptr %t17, ptr %binds.addr.15, align 8
  %t18 = load ptr, ptr %binds.addr.15, align 8
  %t19 = call i32 @node-len(ptr %t18)
  %t20 = srem i32 %t19, 2
  %t21 = icmp ne i32 %t20, 0
  br i1 %t21, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t22 = load ptr, ptr %binds.addr.15, align 8
  %t23 = getelementptr inbounds %Node, ptr %t22, i32 0, i32 1
  %t24 = load i32, ptr %t23, align 4
  %t25 = getelementptr inbounds [31 x i8], ptr @.str.226, i64 0, i64 0
  call void @die-at(i32 %t24, ptr %t25)
  br label %cond.end2
cond.end2:
  %t27 = load ptr, ptr %scope.addr, align 8
  %t28 = call ptr @scope-new(ptr %t27)
  store ptr %t28, ptr %inner.addr.26, align 8
  store i32 0, ptr %i.addr.29, align 4
  br label %while.cond3
while.cond3:
  %t30 = load i32, ptr %i.addr.29, align 4
  %t31 = load ptr, ptr %binds.addr.15, align 8
  %t32 = call i32 @node-len(ptr %t31)
  %t33 = icmp slt i32 %t30, %t32
  br i1 %t33, label %while.body3, label %while.end3
while.body3:
  %t35 = load ptr, ptr %binds.addr.15, align 8
  %t36 = load i32, ptr %i.addr.29, align 4
  %t37 = call ptr @node-at(ptr %t35, i32 %t36)
  store ptr %t37, ptr %bname.addr.34, align 8
  %t39 = load ptr, ptr %binds.addr.15, align 8
  %t40 = load i32, ptr %i.addr.29, align 4
  %t41 = add nsw i32 %t40, 1
  %t42 = call ptr @node-at(ptr %t39, i32 %t41)
  store ptr %t42, ptr %bval-node.addr.38, align 8
  %t43 = load ptr, ptr %bname.addr.34, align 8
  %t44 = getelementptr inbounds %Node, ptr %t43, i32 0, i32 0
  %t45 = load i32, ptr %t44, align 4
  %t46 = icmp ne i32 %t45, 2
  br i1 %t46, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t47 = load ptr, ptr %bname.addr.34, align 8
  %t48 = getelementptr inbounds %Node, ptr %t47, i32 0, i32 1
  %t49 = load i32, ptr %t48, align 4
  %t50 = getelementptr inbounds [33 x i8], ptr @.str.227, i64 0, i64 0
  call void @die-at(i32 %t49, ptr %t50)
  br label %cond.end4
cond.end4:
  store ptr null, ptr %name.addr.51, align 8
  store ptr null, ptr %type-name.addr.52, align 8
  %t53 = load ptr, ptr %bname.addr.34, align 8
  %t54 = getelementptr inbounds %Node, ptr %t53, i32 0, i32 3
  %t55 = load ptr, ptr %t54, align 8
  call void @split-typed(ptr %t55, ptr %name.addr.51, ptr %type-name.addr.52)
  %t56 = load ptr, ptr %type-name.addr.52, align 8
  %t57 = icmp eq ptr %t56, null
  br i1 %t57, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t58 = load ptr, ptr %bname.addr.34, align 8
  %t59 = getelementptr inbounds %Node, ptr %t58, i32 0, i32 1
  %t60 = load i32, ptr %t59, align 4
  %t61 = getelementptr inbounds [27 x i8], ptr @.str.228, i64 0, i64 0
  %t62 = load ptr, ptr %name.addr.51, align 8
  %t63 = call ptr @fmt-s(ptr %t61, ptr %t62)
  call void @die-at(i32 %t60, ptr %t63)
  br label %cond.end5
cond.end5:
  %t65 = load ptr, ptr %type-name.addr.52, align 8
  %t66 = load ptr, ptr %bname.addr.34, align 8
  %t67 = getelementptr inbounds %Node, ptr %t66, i32 0, i32 1
  %t68 = load i32, ptr %t67, align 4
  %t69 = call ptr @parse-type-name(ptr %t65, i32 %t68)
  store ptr %t69, ptr %ty.addr.64, align 8
  %t71 = getelementptr inbounds [13 x i8], ptr @.str.229, i64 0, i64 0
  %t72 = load ptr, ptr %name.addr.51, align 8
  %t73 = load i32, ptr @g-tmp, align 4
  %t74 = call ptr @fmt-sd(ptr %t71, ptr %t72, i32 %t73)
  store ptr %t74, ptr %slot.addr.70, align 8
  %t76 = load ptr, ptr %ty.addr.64, align 8
  %t77 = call i32 @type-size(ptr %t76)
  store i32 %t77, ptr %align.addr.75, align 4
  %t78 = load i32, ptr @g-tmp, align 4
  %t79 = add nsw i32 %t78, 1
  store i32 %t79, ptr @g-tmp, align 4
  %t80 = load ptr, ptr @g-entry-stream, align 8
  %t81 = getelementptr inbounds [28 x i8], ptr @.str.230, i64 0, i64 0
  %t82 = load ptr, ptr %slot.addr.70, align 8
  %t83 = load ptr, ptr %ty.addr.64, align 8
  %t84 = call ptr @type-to-ir(ptr %t83)
  %t85 = load i32, ptr %align.addr.75, align 4
  %t86 = call i32 (ptr, ptr, ...) @fprintf(ptr %t80, ptr %t81, ptr %t82, ptr %t84, i32 %t85)
  %t88 = load ptr, ptr %bval-node.addr.38, align 8
  %t89 = load ptr, ptr %inner.addr.26, align 8
  %t90 = call ptr @emit-node(ptr %t88, ptr %t89)
  store ptr %t90, ptr %v.addr.87, align 8
  %t91 = load ptr, ptr %v.addr.87, align 8
  %t92 = getelementptr inbounds %Val, ptr %t91, i32 0, i32 0
  %t93 = load ptr, ptr %t92, align 8
  %t94 = getelementptr inbounds %Type, ptr %t93, i32 0, i32 0
  %t95 = load i32, ptr %t94, align 4
  %t96 = load ptr, ptr %ty.addr.64, align 8
  %t97 = getelementptr inbounds %Type, ptr %t96, i32 0, i32 0
  %t98 = load i32, ptr %t97, align 4
  %t99 = icmp ne i32 %t95, %t98
  br i1 %t99, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t100 = load ptr, ptr %bval-node.addr.38, align 8
  %t101 = getelementptr inbounds %Node, ptr %t100, i32 0, i32 1
  %t102 = load i32, ptr %t101, align 4
  %t103 = getelementptr inbounds [33 x i8], ptr @.str.231, i64 0, i64 0
  %t104 = load ptr, ptr %name.addr.51, align 8
  %t105 = call ptr @fmt-s(ptr %t103, ptr %t104)
  call void @die-at(i32 %t102, ptr %t105)
  br label %cond.end6
cond.end6:
  %t106 = load ptr, ptr @g-body-stream, align 8
  %t107 = getelementptr inbounds [33 x i8], ptr @.str.232, i64 0, i64 0
  %t108 = load ptr, ptr %ty.addr.64, align 8
  %t109 = call ptr @type-to-ir(ptr %t108)
  %t110 = load ptr, ptr %v.addr.87, align 8
  %t111 = getelementptr inbounds %Val, ptr %t110, i32 0, i32 1
  %t112 = load ptr, ptr %t111, align 8
  %t113 = load ptr, ptr %slot.addr.70, align 8
  %t114 = load i32, ptr %align.addr.75, align 4
  %t115 = call i32 (ptr, ptr, ...) @fprintf(ptr %t106, ptr %t107, ptr %t109, ptr %t112, ptr %t113, i32 %t114)
  %t116 = load ptr, ptr %inner.addr.26, align 8
  %t117 = load ptr, ptr %name.addr.51, align 8
  %t118 = load ptr, ptr %ty.addr.64, align 8
  %t119 = load ptr, ptr %slot.addr.70, align 8
  %t120 = call ptr @scope-define(ptr %t116, ptr %t117, ptr %t118, ptr %t119, i32 1)
  %t121 = load i32, ptr %i.addr.29, align 4
  %t122 = add nsw i32 %t121, 2
  store i32 %t122, ptr %i.addr.29, align 4
  br label %while.cond3
while.end3:
  %t124 = load ptr, ptr @ty-void, align 8
  %t125 = call ptr @alloc-val(ptr %t124, ptr null)
  store ptr %t125, ptr %last.addr.123, align 8
  store i32 2, ptr %j.addr.126, align 4
  br label %while.cond7
while.cond7:
  %t127 = load i32, ptr %j.addr.126, align 4
  %t128 = load ptr, ptr %cc.addr.0, align 8
  %t129 = call i32 @node-len(ptr %t128)
  %t130 = icmp slt i32 %t127, %t129
  br i1 %t130, label %while.body7, label %while.end7
while.body7:
  %t131 = load ptr, ptr %cc.addr.0, align 8
  %t132 = load i32, ptr %j.addr.126, align 4
  %t133 = call ptr @node-at(ptr %t131, i32 %t132)
  %t134 = load ptr, ptr %inner.addr.26, align 8
  %t135 = call ptr @emit-node(ptr %t133, ptr %t134)
  store ptr %t135, ptr %last.addr.123, align 8
  %t136 = load i32, ptr %j.addr.126, align 4
  %t137 = add nsw i32 %t136, 1
  store i32 %t137, ptr %j.addr.126, align 4
  br label %while.cond7
while.end7:
  %t138 = load ptr, ptr %last.addr.123, align 8
  ret ptr %t138
}

define ptr @emit-cond(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %nargs.addr.2 = alloca i32, align 4
  %or.val1 = alloca i1, align 1
  %npairs.addr.16 = alloca i32, align 4
  %id.addr.19 = alloca i32, align 4
  %end-lbl.addr.21 = alloca ptr, align 8
  %i.addr.25 = alloca i32, align 4
  %then-lbl.addr.29 = alloca ptr, align 8
  %next-lbl.addr.34 = alloca ptr, align 8
  %test.addr.45 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t3 = load ptr, ptr %cc.addr.0, align 8
  %t4 = call i32 @node-len(ptr %t3)
  %t5 = sub nsw i32 %t4, 1
  store i32 %t5, ptr %nargs.addr.2, align 4
  %t6 = load i32, ptr %nargs.addr.2, align 4
  %t7 = icmp slt i32 %t6, 2
  store i1 %t7, ptr %or.val1, align 1
  br i1 %t7, label %or.end1, label %or.rhs1
or.rhs1:
  %t8 = load i32, ptr %nargs.addr.2, align 4
  %t9 = srem i32 %t8, 2
  %t10 = icmp ne i32 %t9, 0
  store i1 %t10, ptr %or.val1, align 1
  br label %or.end1
or.end1:
  %t11 = load i1, ptr %or.val1, align 1
  br i1 %t11, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t12 = load ptr, ptr %cc.addr.0, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 1
  %t14 = load i32, ptr %t13, align 4
  %t15 = getelementptr inbounds [35 x i8], ptr @.str.233, i64 0, i64 0
  call void @die-at(i32 %t14, ptr %t15)
  br label %cond.end0
cond.end0:
  %t17 = load i32, ptr %nargs.addr.2, align 4
  %t18 = sdiv i32 %t17, 2
  store i32 %t18, ptr %npairs.addr.16, align 4
  %t20 = call i32 @new-label-id()
  store i32 %t20, ptr %id.addr.19, align 4
  %t22 = getelementptr inbounds [11 x i8], ptr @.str.234, i64 0, i64 0
  %t23 = load i32, ptr %id.addr.19, align 4
  %t24 = call ptr @fmt-i32(ptr %t22, i32 %t23)
  store ptr %t24, ptr %end-lbl.addr.21, align 8
  store i32 0, ptr %i.addr.25, align 4
  br label %while.cond2
while.cond2:
  %t26 = load i32, ptr %i.addr.25, align 4
  %t27 = load i32, ptr %npairs.addr.16, align 4
  %t28 = icmp slt i32 %t26, %t27
  br i1 %t28, label %while.body2, label %while.end2
while.body2:
  %t30 = getelementptr inbounds [15 x i8], ptr @.str.235, i64 0, i64 0
  %t31 = load i32, ptr %id.addr.19, align 4
  %t32 = load i32, ptr %i.addr.25, align 4
  %t33 = call ptr @fmt-i32-i32(ptr %t30, i32 %t31, i32 %t32)
  store ptr %t33, ptr %then-lbl.addr.29, align 8
  %t35 = load ptr, ptr %end-lbl.addr.21, align 8
  store ptr %t35, ptr %next-lbl.addr.34, align 8
  %t36 = load i32, ptr %i.addr.25, align 4
  %t37 = load i32, ptr %npairs.addr.16, align 4
  %t38 = sub nsw i32 %t37, 1
  %t39 = icmp slt i32 %t36, %t38
  br i1 %t39, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t40 = getelementptr inbounds [15 x i8], ptr @.str.236, i64 0, i64 0
  %t41 = load i32, ptr %id.addr.19, align 4
  %t42 = load i32, ptr %i.addr.25, align 4
  %t43 = add nsw i32 %t42, 1
  %t44 = call ptr @fmt-i32-i32(ptr %t40, i32 %t41, i32 %t43)
  store ptr %t44, ptr %next-lbl.addr.34, align 8
  br label %cond.end3
cond.end3:
  %t46 = load ptr, ptr %cc.addr.0, align 8
  %t47 = load i32, ptr %i.addr.25, align 4
  %t48 = mul nsw i32 %t47, 2
  %t49 = add nsw i32 1, %t48
  %t50 = call ptr @node-at(ptr %t46, i32 %t49)
  %t51 = load ptr, ptr %scope.addr, align 8
  %t52 = call ptr @emit-node(ptr %t50, ptr %t51)
  store ptr %t52, ptr %test.addr.45, align 8
  %t53 = load ptr, ptr %test.addr.45, align 8
  %t54 = getelementptr inbounds %Val, ptr %t53, i32 0, i32 0
  %t55 = load ptr, ptr %t54, align 8
  %t56 = getelementptr inbounds %Type, ptr %t55, i32 0, i32 0
  %t57 = load i32, ptr %t56, align 4
  %t58 = icmp ne i32 %t57, 1
  br i1 %t58, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t59 = load ptr, ptr %cc.addr.0, align 8
  %t60 = load i32, ptr %i.addr.25, align 4
  %t61 = mul nsw i32 %t60, 2
  %t62 = add nsw i32 1, %t61
  %t63 = call ptr @node-at(ptr %t59, i32 %t62)
  %t64 = getelementptr inbounds %Node, ptr %t63, i32 0, i32 1
  %t65 = load i32, ptr %t64, align 4
  %t66 = getelementptr inbounds [22 x i8], ptr @.str.237, i64 0, i64 0
  call void @die-at(i32 %t65, ptr %t66)
  br label %cond.end4
cond.end4:
  %t67 = load ptr, ptr @g-body-stream, align 8
  %t68 = getelementptr inbounds [36 x i8], ptr @.str.238, i64 0, i64 0
  %t69 = load ptr, ptr %test.addr.45, align 8
  %t70 = getelementptr inbounds %Val, ptr %t69, i32 0, i32 1
  %t71 = load ptr, ptr %t70, align 8
  %t72 = load ptr, ptr %then-lbl.addr.29, align 8
  %t73 = load ptr, ptr %next-lbl.addr.34, align 8
  %t74 = call i32 (ptr, ptr, ...) @fprintf(ptr %t67, ptr %t68, ptr %t71, ptr %t72, ptr %t73)
  %t75 = load ptr, ptr @g-body-stream, align 8
  %t76 = getelementptr inbounds [5 x i8], ptr @.str.239, i64 0, i64 0
  %t77 = load ptr, ptr %then-lbl.addr.29, align 8
  %t78 = call i32 (ptr, ptr, ...) @fprintf(ptr %t75, ptr %t76, ptr %t77)
  store i32 0, ptr @g-block-term, align 4
  %t79 = load ptr, ptr %cc.addr.0, align 8
  %t80 = load i32, ptr %i.addr.25, align 4
  %t81 = mul nsw i32 %t80, 2
  %t82 = add nsw i32 2, %t81
  %t83 = call ptr @node-at(ptr %t79, i32 %t82)
  %t84 = load ptr, ptr %scope.addr, align 8
  %t85 = call ptr @emit-node(ptr %t83, ptr %t84)
  %t86 = load i32, ptr @g-block-term, align 4
  %t87 = icmp eq i32 %t86, 0
  br i1 %t87, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t88 = load ptr, ptr @g-body-stream, align 8
  %t89 = getelementptr inbounds [17 x i8], ptr @.str.240, i64 0, i64 0
  %t90 = load ptr, ptr %end-lbl.addr.21, align 8
  %t91 = call i32 (ptr, ptr, ...) @fprintf(ptr %t88, ptr %t89, ptr %t90)
  br label %cond.end5
cond.end5:
  %t92 = load i32, ptr %i.addr.25, align 4
  %t93 = load i32, ptr %npairs.addr.16, align 4
  %t94 = sub nsw i32 %t93, 1
  %t95 = icmp slt i32 %t92, %t94
  br i1 %t95, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t96 = load ptr, ptr @g-body-stream, align 8
  %t97 = getelementptr inbounds [5 x i8], ptr @.str.241, i64 0, i64 0
  %t98 = load ptr, ptr %next-lbl.addr.34, align 8
  %t99 = call i32 (ptr, ptr, ...) @fprintf(ptr %t96, ptr %t97, ptr %t98)
  store i32 0, ptr @g-block-term, align 4
  br label %cond.end6
cond.end6:
  %t100 = load i32, ptr %i.addr.25, align 4
  %t101 = add nsw i32 %t100, 1
  store i32 %t101, ptr %i.addr.25, align 4
  br label %while.cond2
while.end2:
  %t102 = load ptr, ptr @g-body-stream, align 8
  %t103 = getelementptr inbounds [5 x i8], ptr @.str.242, i64 0, i64 0
  %t104 = load ptr, ptr %end-lbl.addr.21, align 8
  %t105 = call i32 (ptr, ptr, ...) @fprintf(ptr %t102, ptr %t103, ptr %t104)
  store i32 0, ptr @g-block-term, align 4
  %t106 = load ptr, ptr @ty-void, align 8
  %t107 = call ptr @alloc-val(ptr %t106, ptr null)
  ret ptr %t107
}

define ptr @emit-while(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %id.addr.9 = alloca i32, align 4
  %cond-lbl.addr.11 = alloca ptr, align 8
  %body-lbl.addr.15 = alloca ptr, align 8
  %end-lbl.addr.19 = alloca ptr, align 8
  %cond.addr.31 = alloca ptr, align 8
  %i.addr.59 = alloca i32, align 4
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp slt i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [25 x i8], ptr @.str.243, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = call i32 @new-label-id()
  store i32 %t10, ptr %id.addr.9, align 4
  %t12 = getelementptr inbounds [13 x i8], ptr @.str.244, i64 0, i64 0
  %t13 = load i32, ptr %id.addr.9, align 4
  %t14 = call ptr @fmt-i32(ptr %t12, i32 %t13)
  store ptr %t14, ptr %cond-lbl.addr.11, align 8
  %t16 = getelementptr inbounds [13 x i8], ptr @.str.245, i64 0, i64 0
  %t17 = load i32, ptr %id.addr.9, align 4
  %t18 = call ptr @fmt-i32(ptr %t16, i32 %t17)
  store ptr %t18, ptr %body-lbl.addr.15, align 8
  %t20 = getelementptr inbounds [12 x i8], ptr @.str.246, i64 0, i64 0
  %t21 = load i32, ptr %id.addr.9, align 4
  %t22 = call ptr @fmt-i32(ptr %t20, i32 %t21)
  store ptr %t22, ptr %end-lbl.addr.19, align 8
  %t23 = load ptr, ptr @g-body-stream, align 8
  %t24 = getelementptr inbounds [17 x i8], ptr @.str.247, i64 0, i64 0
  %t25 = load ptr, ptr %cond-lbl.addr.11, align 8
  %t26 = call i32 (ptr, ptr, ...) @fprintf(ptr %t23, ptr %t24, ptr %t25)
  %t27 = load ptr, ptr @g-body-stream, align 8
  %t28 = getelementptr inbounds [5 x i8], ptr @.str.248, i64 0, i64 0
  %t29 = load ptr, ptr %cond-lbl.addr.11, align 8
  %t30 = call i32 (ptr, ptr, ...) @fprintf(ptr %t27, ptr %t28, ptr %t29)
  store i32 0, ptr @g-block-term, align 4
  %t32 = load ptr, ptr %cc.addr.0, align 8
  %t33 = call ptr @node-at(ptr %t32, i32 1)
  %t34 = load ptr, ptr %scope.addr, align 8
  %t35 = call ptr @emit-node(ptr %t33, ptr %t34)
  store ptr %t35, ptr %cond.addr.31, align 8
  %t36 = load ptr, ptr %cond.addr.31, align 8
  %t37 = getelementptr inbounds %Val, ptr %t36, i32 0, i32 0
  %t38 = load ptr, ptr %t37, align 8
  %t39 = getelementptr inbounds %Type, ptr %t38, i32 0, i32 0
  %t40 = load i32, ptr %t39, align 4
  %t41 = icmp ne i32 %t40, 1
  br i1 %t41, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t42 = load ptr, ptr %cc.addr.0, align 8
  %t43 = call ptr @node-at(ptr %t42, i32 1)
  %t44 = getelementptr inbounds %Node, ptr %t43, i32 0, i32 1
  %t45 = load i32, ptr %t44, align 4
  %t46 = getelementptr inbounds [27 x i8], ptr @.str.249, i64 0, i64 0
  call void @die-at(i32 %t45, ptr %t46)
  br label %cond.end1
cond.end1:
  %t47 = load ptr, ptr @g-body-stream, align 8
  %t48 = getelementptr inbounds [36 x i8], ptr @.str.250, i64 0, i64 0
  %t49 = load ptr, ptr %cond.addr.31, align 8
  %t50 = getelementptr inbounds %Val, ptr %t49, i32 0, i32 1
  %t51 = load ptr, ptr %t50, align 8
  %t52 = load ptr, ptr %body-lbl.addr.15, align 8
  %t53 = load ptr, ptr %end-lbl.addr.19, align 8
  %t54 = call i32 (ptr, ptr, ...) @fprintf(ptr %t47, ptr %t48, ptr %t51, ptr %t52, ptr %t53)
  %t55 = load ptr, ptr @g-body-stream, align 8
  %t56 = getelementptr inbounds [5 x i8], ptr @.str.251, i64 0, i64 0
  %t57 = load ptr, ptr %body-lbl.addr.15, align 8
  %t58 = call i32 (ptr, ptr, ...) @fprintf(ptr %t55, ptr %t56, ptr %t57)
  store i32 0, ptr @g-block-term, align 4
  store i32 2, ptr %i.addr.59, align 4
  br label %while.cond2
while.cond2:
  %t60 = load i32, ptr %i.addr.59, align 4
  %t61 = load ptr, ptr %cc.addr.0, align 8
  %t62 = call i32 @node-len(ptr %t61)
  %t63 = icmp slt i32 %t60, %t62
  br i1 %t63, label %while.body2, label %while.end2
while.body2:
  %t64 = load ptr, ptr %cc.addr.0, align 8
  %t65 = load i32, ptr %i.addr.59, align 4
  %t66 = call ptr @node-at(ptr %t64, i32 %t65)
  %t67 = load ptr, ptr %scope.addr, align 8
  %t68 = call ptr @emit-node(ptr %t66, ptr %t67)
  %t69 = load i32, ptr %i.addr.59, align 4
  %t70 = add nsw i32 %t69, 1
  store i32 %t70, ptr %i.addr.59, align 4
  br label %while.cond2
while.end2:
  %t71 = load i32, ptr @g-block-term, align 4
  %t72 = icmp eq i32 %t71, 0
  br i1 %t72, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t73 = load ptr, ptr @g-body-stream, align 8
  %t74 = getelementptr inbounds [17 x i8], ptr @.str.252, i64 0, i64 0
  %t75 = load ptr, ptr %cond-lbl.addr.11, align 8
  %t76 = call i32 (ptr, ptr, ...) @fprintf(ptr %t73, ptr %t74, ptr %t75)
  br label %cond.end3
cond.end3:
  %t77 = load ptr, ptr @g-body-stream, align 8
  %t78 = getelementptr inbounds [5 x i8], ptr @.str.253, i64 0, i64 0
  %t79 = load ptr, ptr %end-lbl.addr.19, align 8
  %t80 = call i32 (ptr, ptr, ...) @fprintf(ptr %t77, ptr %t78, ptr %t79)
  store i32 0, ptr @g-block-term, align 4
  %t81 = load ptr, ptr @ty-void, align 8
  %t82 = call ptr @alloc-val(ptr %t81, ptr null)
  ret ptr %t82
}

define ptr @emit-set(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %target.addr.9 = alloca ptr, align 8
  %set-name.addr.20 = alloca ptr, align 8
  %set-type-ignored.addr.21 = alloca ptr, align 8
  %sym.addr.25 = alloca ptr, align 8
  %or.val3 = alloca i1, align 1
  %v.addr.44 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 3
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [20 x i8], ptr @.str.254, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %target.addr.9, align 8
  %t12 = load ptr, ptr %target.addr.9, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp ne i32 %t14, 2
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %target.addr.9, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = getelementptr inbounds [28 x i8], ptr @.str.255, i64 0, i64 0
  call void @die-at(i32 %t18, ptr %t19)
  br label %cond.end1
cond.end1:
  store ptr null, ptr %set-name.addr.20, align 8
  store ptr null, ptr %set-type-ignored.addr.21, align 8
  %t22 = load ptr, ptr %target.addr.9, align 8
  %t23 = getelementptr inbounds %Node, ptr %t22, i32 0, i32 3
  %t24 = load ptr, ptr %t23, align 8
  call void @split-typed(ptr %t24, ptr %set-name.addr.20, ptr %set-type-ignored.addr.21)
  %t26 = load ptr, ptr %scope.addr, align 8
  %t27 = load ptr, ptr %set-name.addr.20, align 8
  %t28 = call ptr @scope-lookup(ptr %t26, ptr %t27)
  store ptr %t28, ptr %sym.addr.25, align 8
  %t29 = load ptr, ptr %sym.addr.25, align 8
  %t30 = icmp eq ptr %t29, null
  store i1 %t30, ptr %or.val3, align 1
  br i1 %t30, label %or.end3, label %or.rhs3
or.rhs3:
  %t31 = load ptr, ptr %sym.addr.25, align 8
  %t32 = getelementptr inbounds %Sym, ptr %t31, i32 0, i32 3
  %t33 = load i32, ptr %t32, align 4
  %t34 = icmp eq i32 %t33, 0
  store i1 %t34, ptr %or.val3, align 1
  br label %or.end3
or.end3:
  %t35 = load i1, ptr %or.val3, align 1
  br i1 %t35, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t36 = load ptr, ptr %target.addr.9, align 8
  %t37 = getelementptr inbounds %Node, ptr %t36, i32 0, i32 1
  %t38 = load i32, ptr %t37, align 4
  %t39 = getelementptr inbounds [27 x i8], ptr @.str.256, i64 0, i64 0
  %t40 = load ptr, ptr %target.addr.9, align 8
  %t41 = getelementptr inbounds %Node, ptr %t40, i32 0, i32 3
  %t42 = load ptr, ptr %t41, align 8
  %t43 = call ptr @fmt-s(ptr %t39, ptr %t42)
  call void @die-at(i32 %t38, ptr %t43)
  br label %cond.end2
cond.end2:
  %t45 = load ptr, ptr %cc.addr.0, align 8
  %t46 = call ptr @node-at(ptr %t45, i32 2)
  %t47 = load ptr, ptr %scope.addr, align 8
  %t48 = call ptr @emit-node(ptr %t46, ptr %t47)
  store ptr %t48, ptr %v.addr.44, align 8
  %t49 = load ptr, ptr %v.addr.44, align 8
  %t50 = getelementptr inbounds %Val, ptr %t49, i32 0, i32 0
  %t51 = load ptr, ptr %t50, align 8
  %t52 = getelementptr inbounds %Type, ptr %t51, i32 0, i32 0
  %t53 = load i32, ptr %t52, align 4
  %t54 = load ptr, ptr %sym.addr.25, align 8
  %t55 = getelementptr inbounds %Sym, ptr %t54, i32 0, i32 1
  %t56 = load ptr, ptr %t55, align 8
  %t57 = getelementptr inbounds %Type, ptr %t56, i32 0, i32 0
  %t58 = load i32, ptr %t57, align 4
  %t59 = icmp ne i32 %t53, %t58
  br i1 %t59, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t60 = load ptr, ptr %cc.addr.0, align 8
  %t61 = getelementptr inbounds %Node, ptr %t60, i32 0, i32 1
  %t62 = load i32, ptr %t61, align 4
  %t63 = getelementptr inbounds [29 x i8], ptr @.str.257, i64 0, i64 0
  %t64 = load ptr, ptr %target.addr.9, align 8
  %t65 = getelementptr inbounds %Node, ptr %t64, i32 0, i32 3
  %t66 = load ptr, ptr %t65, align 8
  %t67 = call ptr @fmt-s(ptr %t63, ptr %t66)
  call void @die-at(i32 %t62, ptr %t67)
  br label %cond.end4
cond.end4:
  %t68 = load ptr, ptr @g-body-stream, align 8
  %t69 = getelementptr inbounds [33 x i8], ptr @.str.258, i64 0, i64 0
  %t70 = load ptr, ptr %sym.addr.25, align 8
  %t71 = getelementptr inbounds %Sym, ptr %t70, i32 0, i32 1
  %t72 = load ptr, ptr %t71, align 8
  %t73 = call ptr @type-to-ir(ptr %t72)
  %t74 = load ptr, ptr %v.addr.44, align 8
  %t75 = getelementptr inbounds %Val, ptr %t74, i32 0, i32 1
  %t76 = load ptr, ptr %t75, align 8
  %t77 = load ptr, ptr %sym.addr.25, align 8
  %t78 = getelementptr inbounds %Sym, ptr %t77, i32 0, i32 2
  %t79 = load ptr, ptr %t78, align 8
  %t80 = load ptr, ptr %sym.addr.25, align 8
  %t81 = getelementptr inbounds %Sym, ptr %t80, i32 0, i32 1
  %t82 = load ptr, ptr %t81, align 8
  %t83 = call i32 @type-size(ptr %t82)
  %t84 = call i32 (ptr, ptr, ...) @fprintf(ptr %t68, ptr %t69, ptr %t73, ptr %t76, ptr %t79, i32 %t83)
  %t85 = load ptr, ptr @ty-void, align 8
  %t86 = call ptr @alloc-val(ptr %t85, ptr null)
  ret ptr %t86
}

define ptr @emit-inc(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %target.addr.9 = alloca ptr, align 8
  %inc-name.addr.20 = alloca ptr, align 8
  %inc-type-ignored.addr.21 = alloca ptr, align 8
  %sym.addr.25 = alloca ptr, align 8
  %or.val3 = alloca i1, align 1
  %ir.addr.53 = alloca ptr, align 8
  %align.addr.58 = alloca i32, align 4
  %t1.addr.63 = alloca ptr, align 8
  %t2.addr.74 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [19 x i8], ptr @.str.259, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %target.addr.9, align 8
  %t12 = load ptr, ptr %target.addr.9, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp ne i32 %t14, 2
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %target.addr.9, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = getelementptr inbounds [28 x i8], ptr @.str.260, i64 0, i64 0
  call void @die-at(i32 %t18, ptr %t19)
  br label %cond.end1
cond.end1:
  store ptr null, ptr %inc-name.addr.20, align 8
  store ptr null, ptr %inc-type-ignored.addr.21, align 8
  %t22 = load ptr, ptr %target.addr.9, align 8
  %t23 = getelementptr inbounds %Node, ptr %t22, i32 0, i32 3
  %t24 = load ptr, ptr %t23, align 8
  call void @split-typed(ptr %t24, ptr %inc-name.addr.20, ptr %inc-type-ignored.addr.21)
  %t26 = load ptr, ptr %scope.addr, align 8
  %t27 = load ptr, ptr %inc-name.addr.20, align 8
  %t28 = call ptr @scope-lookup(ptr %t26, ptr %t27)
  store ptr %t28, ptr %sym.addr.25, align 8
  %t29 = load ptr, ptr %sym.addr.25, align 8
  %t30 = icmp eq ptr %t29, null
  store i1 %t30, ptr %or.val3, align 1
  br i1 %t30, label %or.end3, label %or.rhs3
or.rhs3:
  %t31 = load ptr, ptr %sym.addr.25, align 8
  %t32 = getelementptr inbounds %Sym, ptr %t31, i32 0, i32 3
  %t33 = load i32, ptr %t32, align 4
  %t34 = icmp eq i32 %t33, 0
  store i1 %t34, ptr %or.val3, align 1
  br label %or.end3
or.end3:
  %t35 = load i1, ptr %or.val3, align 1
  br i1 %t35, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t36 = load ptr, ptr %target.addr.9, align 8
  %t37 = getelementptr inbounds %Node, ptr %t36, i32 0, i32 1
  %t38 = load i32, ptr %t37, align 4
  %t39 = getelementptr inbounds [27 x i8], ptr @.str.261, i64 0, i64 0
  %t40 = load ptr, ptr %target.addr.9, align 8
  %t41 = getelementptr inbounds %Node, ptr %t40, i32 0, i32 3
  %t42 = load ptr, ptr %t41, align 8
  %t43 = call ptr @fmt-s(ptr %t39, ptr %t42)
  call void @die-at(i32 %t38, ptr %t43)
  br label %cond.end2
cond.end2:
  %t44 = load ptr, ptr %sym.addr.25, align 8
  %t45 = getelementptr inbounds %Sym, ptr %t44, i32 0, i32 1
  %t46 = load ptr, ptr %t45, align 8
  %t47 = call i32 @is-int-type(ptr %t46)
  %t48 = icmp eq i32 %t47, 0
  br i1 %t48, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t49 = load ptr, ptr %cc.addr.0, align 8
  %t50 = getelementptr inbounds %Node, ptr %t49, i32 0, i32 1
  %t51 = load i32, ptr %t50, align 4
  %t52 = getelementptr inbounds [22 x i8], ptr @.str.262, i64 0, i64 0
  call void @die-at(i32 %t51, ptr %t52)
  br label %cond.end4
cond.end4:
  %t54 = load ptr, ptr %sym.addr.25, align 8
  %t55 = getelementptr inbounds %Sym, ptr %t54, i32 0, i32 1
  %t56 = load ptr, ptr %t55, align 8
  %t57 = call ptr @type-to-ir(ptr %t56)
  store ptr %t57, ptr %ir.addr.53, align 8
  %t59 = load ptr, ptr %sym.addr.25, align 8
  %t60 = getelementptr inbounds %Sym, ptr %t59, i32 0, i32 1
  %t61 = load ptr, ptr %t60, align 8
  %t62 = call i32 @type-size(ptr %t61)
  store i32 %t62, ptr %align.addr.58, align 4
  %t64 = call ptr @new-tmp()
  store ptr %t64, ptr %t1.addr.63, align 8
  %t65 = load ptr, ptr @g-body-stream, align 8
  %t66 = getelementptr inbounds [34 x i8], ptr @.str.263, i64 0, i64 0
  %t67 = load ptr, ptr %t1.addr.63, align 8
  %t68 = load ptr, ptr %ir.addr.53, align 8
  %t69 = load ptr, ptr %sym.addr.25, align 8
  %t70 = getelementptr inbounds %Sym, ptr %t69, i32 0, i32 2
  %t71 = load ptr, ptr %t70, align 8
  %t72 = load i32, ptr %align.addr.58, align 4
  %t73 = call i32 (ptr, ptr, ...) @fprintf(ptr %t65, ptr %t66, ptr %t67, ptr %t68, ptr %t71, i32 %t72)
  %t75 = call ptr @new-tmp()
  store ptr %t75, ptr %t2.addr.74, align 8
  %t76 = load ptr, ptr @g-body-stream, align 8
  %t77 = getelementptr inbounds [25 x i8], ptr @.str.264, i64 0, i64 0
  %t78 = load ptr, ptr %t2.addr.74, align 8
  %t79 = load ptr, ptr %ir.addr.53, align 8
  %t80 = load ptr, ptr %t1.addr.63, align 8
  %t81 = call i32 (ptr, ptr, ...) @fprintf(ptr %t76, ptr %t77, ptr %t78, ptr %t79, ptr %t80)
  %t82 = load ptr, ptr @g-body-stream, align 8
  %t83 = getelementptr inbounds [33 x i8], ptr @.str.265, i64 0, i64 0
  %t84 = load ptr, ptr %ir.addr.53, align 8
  %t85 = load ptr, ptr %t2.addr.74, align 8
  %t86 = load ptr, ptr %sym.addr.25, align 8
  %t87 = getelementptr inbounds %Sym, ptr %t86, i32 0, i32 2
  %t88 = load ptr, ptr %t87, align 8
  %t89 = load i32, ptr %align.addr.58, align 4
  %t90 = call i32 (ptr, ptr, ...) @fprintf(ptr %t82, ptr %t83, ptr %t84, ptr %t85, ptr %t88, i32 %t89)
  %t91 = load ptr, ptr @ty-void, align 8
  %t92 = call ptr @alloc-val(ptr %t91, ptr null)
  ret ptr %t92
}

define ptr @emit-macro-expand(ptr %call.arg, ptr %scope.arg, ptr %macro-def.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %macro-def.addr = alloca ptr, align 8
  store ptr %macro-def.arg, ptr %macro-def.addr, align 8
  %mdef.addr.0 = alloca ptr, align 8
  %nargs.addr.2 = alloca i32, align 4
  %args-arr.addr.37 = alloca ptr, align 8
  %regular-params.addr.45 = alloca i32, align 4
  %i.addr.49 = alloca i32, align 4
  %rest-list.addr.75 = alloca ptr, align 8
  %rj.addr.76 = alloca i32, align 4
  %addr.addr.94 = alloca i64, align 8
  %err.addr.96 = alloca ptr, align 8
  %result.addr.121 = alloca ptr, align 8
  %t1 = load ptr, ptr %macro-def.addr, align 8
  store ptr %t1, ptr %mdef.addr.0, align 8
  %t3 = load ptr, ptr %call.addr, align 8
  %t4 = call i32 @node-len(ptr %t3)
  %t5 = sub nsw i32 %t4, 1
  store i32 %t5, ptr %nargs.addr.2, align 4
  %t6 = load ptr, ptr %mdef.addr.0, align 8
  %t7 = getelementptr inbounds %MacroDef, ptr %t6, i32 0, i32 3
  %t8 = load i32, ptr %t7, align 4
  %t9 = icmp ne i32 %t8, 0
  br i1 %t9, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t10 = load i32, ptr %nargs.addr.2, align 4
  %t11 = load ptr, ptr %mdef.addr.0, align 8
  %t12 = getelementptr inbounds %MacroDef, ptr %t11, i32 0, i32 2
  %t13 = load i32, ptr %t12, align 4
  %t14 = sub nsw i32 %t13, 1
  %t15 = icmp slt i32 %t10, %t14
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %call.addr, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = getelementptr inbounds [23 x i8], ptr @.str.266, i64 0, i64 0
  %t20 = sext i32 0 to i64
  %t21 = call ptr @fmt-s(ptr %t19, i64 %t20)
  call void @die-at(i32 %t18, ptr %t21)
  br label %cond.end1
cond.end1:
  br label %cond.end0
cond.end0:
  %t22 = load ptr, ptr %mdef.addr.0, align 8
  %t23 = getelementptr inbounds %MacroDef, ptr %t22, i32 0, i32 3
  %t24 = load i32, ptr %t23, align 4
  %t25 = icmp eq i32 %t24, 0
  br i1 %t25, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t26 = load i32, ptr %nargs.addr.2, align 4
  %t27 = load ptr, ptr %mdef.addr.0, align 8
  %t28 = getelementptr inbounds %MacroDef, ptr %t27, i32 0, i32 2
  %t29 = load i32, ptr %t28, align 4
  %t30 = icmp ne i32 %t26, %t29
  br i1 %t30, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t31 = load ptr, ptr %call.addr, align 8
  %t32 = getelementptr inbounds %Node, ptr %t31, i32 0, i32 1
  %t33 = load i32, ptr %t32, align 4
  %t34 = getelementptr inbounds [28 x i8], ptr @.str.267, i64 0, i64 0
  %t35 = sext i32 0 to i64
  %t36 = call ptr @fmt-s(ptr %t34, i64 %t35)
  call void @die-at(i32 %t33, ptr %t36)
  br label %cond.end3
cond.end3:
  br label %cond.end2
cond.end2:
  %t38 = load ptr, ptr %mdef.addr.0, align 8
  %t39 = getelementptr inbounds %MacroDef, ptr %t38, i32 0, i32 2
  %t40 = load i32, ptr %t39, align 4
  %t41 = sext i32 %t40 to i64
  %t42 = sext i32 8 to i64
  %t43 = mul nsw i64 %t41, %t42
  %t44 = call ptr @malloc(i64 %t43)
  store ptr %t44, ptr %args-arr.addr.37, align 8
  %t46 = load ptr, ptr %mdef.addr.0, align 8
  %t47 = getelementptr inbounds %MacroDef, ptr %t46, i32 0, i32 2
  %t48 = load i32, ptr %t47, align 4
  store i32 %t48, ptr %regular-params.addr.45, align 4
  store i32 0, ptr %i.addr.49, align 4
  %t50 = load ptr, ptr %mdef.addr.0, align 8
  %t51 = getelementptr inbounds %MacroDef, ptr %t50, i32 0, i32 3
  %t52 = load i32, ptr %t51, align 4
  %t53 = icmp ne i32 %t52, 0
  br i1 %t53, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t54 = load ptr, ptr %mdef.addr.0, align 8
  %t55 = getelementptr inbounds %MacroDef, ptr %t54, i32 0, i32 2
  %t56 = load i32, ptr %t55, align 4
  %t57 = sub nsw i32 %t56, 1
  store i32 %t57, ptr %regular-params.addr.45, align 4
  br label %cond.end4
cond.end4:
  br label %while.cond5
while.cond5:
  %t58 = load i32, ptr %i.addr.49, align 4
  %t59 = load i32, ptr %regular-params.addr.45, align 4
  %t60 = icmp slt i32 %t58, %t59
  br i1 %t60, label %while.body5, label %while.end5
while.body5:
  %t61 = load ptr, ptr %args-arr.addr.37, align 8
  %t62 = load i32, ptr %i.addr.49, align 4
  %t63 = sext i32 %t62 to i64
  %t64 = load ptr, ptr %call.addr, align 8
  %t65 = load i32, ptr %i.addr.49, align 4
  %t66 = add nsw i32 %t65, 1
  %t67 = call ptr @node-at(ptr %t64, i32 %t66)
  %t68 = getelementptr inbounds ptr, ptr %t61, i64 %t63
  store ptr %t67, ptr %t68, align 8
  %t69 = load i32, ptr %i.addr.49, align 4
  %t70 = add nsw i32 %t69, 1
  store i32 %t70, ptr %i.addr.49, align 4
  br label %while.cond5
while.end5:
  %t71 = load ptr, ptr %mdef.addr.0, align 8
  %t72 = getelementptr inbounds %MacroDef, ptr %t71, i32 0, i32 3
  %t73 = load i32, ptr %t72, align 4
  %t74 = icmp ne i32 %t73, 0
  br i1 %t74, label %cond.then6.0, label %cond.end6
cond.then6.0:
  store ptr null, ptr %rest-list.addr.75, align 8
  %t77 = load i32, ptr %nargs.addr.2, align 4
  store i32 %t77, ptr %rj.addr.76, align 4
  br label %while.cond7
while.cond7:
  %t78 = load i32, ptr %rj.addr.76, align 4
  %t79 = load i32, ptr %regular-params.addr.45, align 4
  %t80 = icmp sgt i32 %t78, %t79
  br i1 %t80, label %while.body7, label %while.end7
while.body7:
  %t81 = load i32, ptr %rj.addr.76, align 4
  %t82 = sub nsw i32 %t81, 1
  store i32 %t82, ptr %rj.addr.76, align 4
  %t83 = load ptr, ptr %call.addr, align 8
  %t84 = load i32, ptr %rj.addr.76, align 4
  %t85 = add nsw i32 %t84, 1
  %t86 = call ptr @node-at(ptr %t83, i32 %t85)
  %t87 = load ptr, ptr %rest-list.addr.75, align 8
  %t88 = call ptr @make-cell(ptr %t86, ptr %t87, i32 0)
  store ptr %t88, ptr %rest-list.addr.75, align 8
  br label %while.cond7
while.end7:
  %t89 = load ptr, ptr %args-arr.addr.37, align 8
  %t90 = load i32, ptr %regular-params.addr.45, align 4
  %t91 = sext i32 %t90 to i64
  %t92 = load ptr, ptr %rest-list.addr.75, align 8
  %t93 = getelementptr inbounds ptr, ptr %t89, i64 %t91
  store ptr %t92, ptr %t93, align 8
  br label %cond.end6
cond.end6:
  %t95 = sext i32 0 to i64
  store i64 %t95, ptr %addr.addr.94, align 8
  %t97 = load ptr, ptr @g-jit, align 8
  %t98 = load ptr, ptr %mdef.addr.0, align 8
  %t99 = getelementptr inbounds %MacroDef, ptr %t98, i32 0, i32 1
  %t100 = load ptr, ptr %t99, align 8
  %t101 = call ptr @LLVMOrcLLJITLookup(ptr %t97, ptr %addr.addr.94, ptr %t100)
  store ptr %t101, ptr %err.addr.96, align 8
  %t102 = load ptr, ptr %err.addr.96, align 8
  %t103 = icmp ne ptr %t102, null
  br i1 %t103, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t104 = load ptr, ptr @stderr, align 8
  %t105 = getelementptr inbounds [35 x i8], ptr @.str.268, i64 0, i64 0
  %t106 = load ptr, ptr @g-source-path, align 8
  %t107 = load ptr, ptr %mdef.addr.0, align 8
  %t108 = getelementptr inbounds %MacroDef, ptr %t107, i32 0, i32 0
  %t109 = load ptr, ptr %t108, align 8
  %t110 = call i32 (ptr, ptr, ...) @fprintf(ptr %t104, ptr %t105, ptr %t106, ptr %t109)
  call void @exit(i32 1)
  br label %cond.end8
cond.end8:
  %t111 = load i64, ptr %addr.addr.94, align 8
  %t112 = inttoptr i64 %t111 to ptr
  %t113 = icmp eq ptr %t112, null
  br i1 %t113, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t114 = load ptr, ptr @stderr, align 8
  %t115 = getelementptr inbounds [40 x i8], ptr @.str.269, i64 0, i64 0
  %t116 = load ptr, ptr @g-source-path, align 8
  %t117 = load ptr, ptr %mdef.addr.0, align 8
  %t118 = getelementptr inbounds %MacroDef, ptr %t117, i32 0, i32 0
  %t119 = load ptr, ptr %t118, align 8
  %t120 = call i32 (ptr, ptr, ...) @fprintf(ptr %t114, ptr %t115, ptr %t116, ptr %t119)
  call void @exit(i32 1)
  br label %cond.end9
cond.end9:
  %t122 = load i64, ptr %addr.addr.94, align 8
  %t123 = inttoptr i64 %t122 to ptr
  %t124 = load ptr, ptr %args-arr.addr.37, align 8
  %t125 = call ptr %t123(ptr %t124)
  store ptr %t125, ptr %result.addr.121, align 8
  %t126 = load ptr, ptr %args-arr.addr.37, align 8
  call void @free(ptr %t126)
  %t127 = load ptr, ptr %result.addr.121, align 8
  %t128 = icmp eq ptr %t127, null
  br i1 %t128, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t129 = load ptr, ptr @stderr, align 8
  %t130 = getelementptr inbounds [31 x i8], ptr @.str.270, i64 0, i64 0
  %t131 = load ptr, ptr @g-source-path, align 8
  %t132 = load ptr, ptr %mdef.addr.0, align 8
  %t133 = getelementptr inbounds %MacroDef, ptr %t132, i32 0, i32 0
  %t134 = load ptr, ptr %t133, align 8
  %t135 = call i32 (ptr, ptr, ...) @fprintf(ptr %t129, ptr %t130, ptr %t131, ptr %t134)
  call void @exit(i32 1)
  br label %cond.end10
cond.end10:
  %t136 = load ptr, ptr %result.addr.121, align 8
  %t137 = load ptr, ptr %scope.addr, align 8
  %t138 = call ptr @emit-node(ptr %t136, ptr %t137)
  ret ptr %t138
}

define ptr @emit-list(ptr %n.arg, ptr %scope.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %nn.addr.0 = alloca ptr, align 8
  %head.addr.9 = alloca ptr, align 8
  %h.addr.20 = alloca ptr, align 8
  %mi.addr.24 = alloca i32, align 4
  %mdef.addr.28 = alloca ptr, align 8
  %and.val5 = alloca i1, align 1
  %tmp.addr.53 = alloca ptr, align 8
  %op.addr.243 = alloca ptr, align 8
  %sym.addr.252 = alloca ptr, align 8
  %t1 = load ptr, ptr %n.addr, align 8
  store ptr %t1, ptr %nn.addr.0, align 8
  %t2 = load ptr, ptr %nn.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp eq i32 %t3, 0
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %nn.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [11 x i8], ptr @.str.271, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %nn.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 0)
  store ptr %t11, ptr %head.addr.9, align 8
  %t12 = load ptr, ptr %head.addr.9, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp ne i32 %t14, 2
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %head.addr.9, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = getelementptr inbounds [25 x i8], ptr @.str.272, i64 0, i64 0
  call void @die-at(i32 %t18, ptr %t19)
  br label %cond.end1
cond.end1:
  %t21 = load ptr, ptr %head.addr.9, align 8
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 3
  %t23 = load ptr, ptr %t22, align 8
  store ptr %t23, ptr %h.addr.20, align 8
  store i32 0, ptr %mi.addr.24, align 4
  br label %while.cond2
while.cond2:
  %t25 = load i32, ptr %mi.addr.24, align 4
  %t26 = load i32, ptr @g-num-macros, align 4
  %t27 = icmp slt i32 %t25, %t26
  br i1 %t27, label %while.body2, label %while.end2
while.body2:
  %t29 = load ptr, ptr @g-macros, align 8
  %t30 = load i32, ptr %mi.addr.24, align 4
  %t31 = sext i32 %t30 to i64
  %t32 = getelementptr inbounds %MacroDef, ptr %t29, i64 %t31
  store ptr %t32, ptr %mdef.addr.28, align 8
  %t33 = load ptr, ptr %mdef.addr.28, align 8
  %t34 = getelementptr inbounds %MacroDef, ptr %t33, i32 0, i32 0
  %t35 = load ptr, ptr %t34, align 8
  %t36 = load ptr, ptr %h.addr.20, align 8
  %t37 = call i32 @strcmp(ptr %t35, ptr %t36)
  %t38 = icmp eq i32 %t37, 0
  br i1 %t38, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t39 = load ptr, ptr %n.addr, align 8
  %t40 = load ptr, ptr %scope.addr, align 8
  %t41 = load ptr, ptr %mdef.addr.28, align 8
  %t42 = call ptr @emit-macro-expand(ptr %t39, ptr %t40, ptr %t41)
  ret ptr %t42
cond.end3:
  %t43 = load i32, ptr %mi.addr.24, align 4
  %t44 = add nsw i32 %t43, 1
  store i32 %t44, ptr %mi.addr.24, align 4
  br label %while.cond2
while.end2:
  %t45 = load ptr, ptr %h.addr.20, align 8
  %t46 = getelementptr inbounds [7 x i8], ptr @.str.273, i64 0, i64 0
  %t47 = call i32 @strcmp(ptr %t45, ptr %t46)
  %t48 = icmp eq i32 %t47, 0
  store i1 %t48, ptr %and.val5, align 1
  br i1 %t48, label %and.rhs5, label %and.end5
and.rhs5:
  %t49 = load ptr, ptr %nn.addr.0, align 8
  %t50 = call i32 @node-len(ptr %t49)
  %t51 = icmp eq i32 %t50, 1
  store i1 %t51, ptr %and.val5, align 1
  br label %and.end5
and.end5:
  %t52 = load i1, ptr %and.val5, align 1
  br i1 %t52, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t54 = call ptr @new-tmp()
  store ptr %t54, ptr %tmp.addr.53, align 8
  %t55 = load ptr, ptr @g-body-stream, align 8
  %t56 = getelementptr inbounds [35 x i8], ptr @.str.274, i64 0, i64 0
  %t57 = load ptr, ptr %tmp.addr.53, align 8
  %t58 = call i32 (ptr, ptr, ...) @fprintf(ptr %t55, ptr %t56, ptr %t57)
  %t59 = load ptr, ptr @ty-ptr, align 8
  %t60 = load ptr, ptr %tmp.addr.53, align 8
  %t61 = call ptr @alloc-val(ptr %t59, ptr %t60)
  ret ptr %t61
cond.end4:
  %t62 = load ptr, ptr %h.addr.20, align 8
  %t63 = getelementptr inbounds [14 x i8], ptr @.str.275, i64 0, i64 0
  %t64 = call i32 @strcmp(ptr %t62, ptr %t63)
  %t65 = icmp eq i32 %t64, 0
  br i1 %t65, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t66 = load ptr, ptr %n.addr, align 8
  %t67 = load ptr, ptr %scope.addr, align 8
  %t68 = call ptr @emit-funcall-ptr-1(ptr %t66, ptr %t67)
  ret ptr %t68
cond.end6:
  %t69 = load ptr, ptr %h.addr.20, align 8
  %t70 = getelementptr inbounds [7 x i8], ptr @.str.276, i64 0, i64 0
  %t71 = call i32 @strcmp(ptr %t69, ptr %t70)
  %t72 = icmp eq i32 %t71, 0
  br i1 %t72, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t73 = load ptr, ptr %n.addr, align 8
  %t74 = load ptr, ptr %scope.addr, align 8
  %t75 = call ptr @emit-return(ptr %t73, ptr %t74)
  ret ptr %t75
cond.end7:
  %t76 = load ptr, ptr %h.addr.20, align 8
  %t77 = getelementptr inbounds [3 x i8], ptr @.str.277, i64 0, i64 0
  %t78 = call i32 @strcmp(ptr %t76, ptr %t77)
  %t79 = icmp eq i32 %t78, 0
  br i1 %t79, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t80 = load ptr, ptr %n.addr, align 8
  %t81 = load ptr, ptr %scope.addr, align 8
  %t82 = call ptr @emit-do(ptr %t80, ptr %t81)
  ret ptr %t82
cond.end8:
  %t83 = load ptr, ptr %h.addr.20, align 8
  %t84 = getelementptr inbounds [4 x i8], ptr @.str.278, i64 0, i64 0
  %t85 = call i32 @strcmp(ptr %t83, ptr %t84)
  %t86 = icmp eq i32 %t85, 0
  br i1 %t86, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t87 = load ptr, ptr %n.addr, align 8
  %t88 = load ptr, ptr %scope.addr, align 8
  %t89 = call ptr @emit-let(ptr %t87, ptr %t88)
  ret ptr %t89
cond.end9:
  %t90 = load ptr, ptr %h.addr.20, align 8
  %t91 = getelementptr inbounds [5 x i8], ptr @.str.279, i64 0, i64 0
  %t92 = call i32 @strcmp(ptr %t90, ptr %t91)
  %t93 = icmp eq i32 %t92, 0
  br i1 %t93, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t94 = load ptr, ptr %n.addr, align 8
  %t95 = load ptr, ptr %scope.addr, align 8
  %t96 = call ptr @emit-cond(ptr %t94, ptr %t95)
  ret ptr %t96
cond.end10:
  %t97 = load ptr, ptr %h.addr.20, align 8
  %t98 = getelementptr inbounds [6 x i8], ptr @.str.280, i64 0, i64 0
  %t99 = call i32 @strcmp(ptr %t97, ptr %t98)
  %t100 = icmp eq i32 %t99, 0
  br i1 %t100, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t101 = load ptr, ptr %n.addr, align 8
  %t102 = call ptr @emit-quote(ptr %t101)
  ret ptr %t102
cond.end11:
  %t103 = load ptr, ptr %h.addr.20, align 8
  %t104 = getelementptr inbounds [11 x i8], ptr @.str.281, i64 0, i64 0
  %t105 = call i32 @strcmp(ptr %t103, ptr %t104)
  %t106 = icmp eq i32 %t105, 0
  br i1 %t106, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t107 = load ptr, ptr %n.addr, align 8
  %t108 = load ptr, ptr %scope.addr, align 8
  %t109 = call ptr @emit-quasiquote(ptr %t107, ptr %t108)
  ret ptr %t109
cond.end12:
  %t110 = load ptr, ptr %h.addr.20, align 8
  %t111 = getelementptr inbounds [6 x i8], ptr @.str.282, i64 0, i64 0
  %t112 = call i32 @strcmp(ptr %t110, ptr %t111)
  %t113 = icmp eq i32 %t112, 0
  br i1 %t113, label %cond.then13.0, label %cond.end13
cond.then13.0:
  %t114 = load ptr, ptr %n.addr, align 8
  %t115 = load ptr, ptr %scope.addr, align 8
  %t116 = call ptr @emit-while(ptr %t114, ptr %t115)
  ret ptr %t116
cond.end13:
  %t117 = load ptr, ptr %h.addr.20, align 8
  %t118 = getelementptr inbounds [5 x i8], ptr @.str.283, i64 0, i64 0
  %t119 = call i32 @strcmp(ptr %t117, ptr %t118)
  %t120 = icmp eq i32 %t119, 0
  br i1 %t120, label %cond.then14.0, label %cond.end14
cond.then14.0:
  %t121 = load ptr, ptr %n.addr, align 8
  %t122 = load ptr, ptr %scope.addr, align 8
  %t123 = call ptr @emit-set(ptr %t121, ptr %t122)
  ret ptr %t123
cond.end14:
  %t124 = load ptr, ptr %h.addr.20, align 8
  %t125 = getelementptr inbounds [5 x i8], ptr @.str.284, i64 0, i64 0
  %t126 = call i32 @strcmp(ptr %t124, ptr %t125)
  %t127 = icmp eq i32 %t126, 0
  br i1 %t127, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t128 = load ptr, ptr %n.addr, align 8
  %t129 = load ptr, ptr %scope.addr, align 8
  %t130 = call ptr @emit-inc(ptr %t128, ptr %t129)
  ret ptr %t130
cond.end15:
  %t131 = load ptr, ptr %h.addr.20, align 8
  %t132 = getelementptr inbounds [4 x i8], ptr @.str.285, i64 0, i64 0
  %t133 = call i32 @strcmp(ptr %t131, ptr %t132)
  %t134 = icmp eq i32 %t133, 0
  br i1 %t134, label %cond.then16.0, label %cond.end16
cond.then16.0:
  %t135 = load ptr, ptr %n.addr, align 8
  %t136 = load ptr, ptr %scope.addr, align 8
  %t137 = call ptr @emit-not(ptr %t135, ptr %t136)
  ret ptr %t137
cond.end16:
  %t138 = load ptr, ptr %h.addr.20, align 8
  %t139 = getelementptr inbounds [4 x i8], ptr @.str.286, i64 0, i64 0
  %t140 = call i32 @strcmp(ptr %t138, ptr %t139)
  %t141 = icmp eq i32 %t140, 0
  br i1 %t141, label %cond.then17.0, label %cond.end17
cond.then17.0:
  %t142 = load ptr, ptr %n.addr, align 8
  %t143 = load ptr, ptr %scope.addr, align 8
  %t144 = call ptr @emit-short-circuit(ptr %t142, ptr %t143, i32 1)
  ret ptr %t144
cond.end17:
  %t145 = load ptr, ptr %h.addr.20, align 8
  %t146 = getelementptr inbounds [3 x i8], ptr @.str.287, i64 0, i64 0
  %t147 = call i32 @strcmp(ptr %t145, ptr %t146)
  %t148 = icmp eq i32 %t147, 0
  br i1 %t148, label %cond.then18.0, label %cond.end18
cond.then18.0:
  %t149 = load ptr, ptr %n.addr, align 8
  %t150 = load ptr, ptr %scope.addr, align 8
  %t151 = call ptr @emit-short-circuit(ptr %t149, ptr %t150, i32 0)
  ret ptr %t151
cond.end18:
  %t152 = load ptr, ptr %h.addr.20, align 8
  %t153 = getelementptr inbounds [5 x i8], ptr @.str.288, i64 0, i64 0
  %t154 = call i32 @strcmp(ptr %t152, ptr %t153)
  %t155 = icmp eq i32 %t154, 0
  br i1 %t155, label %cond.then19.0, label %cond.end19
cond.then19.0:
  %t156 = load ptr, ptr %n.addr, align 8
  %t157 = load ptr, ptr %scope.addr, align 8
  %t158 = call ptr @emit-cast(ptr %t156, ptr %t157)
  ret ptr %t158
cond.end19:
  %t159 = load ptr, ptr %h.addr.20, align 8
  %t160 = getelementptr inbounds [8 x i8], ptr @.str.289, i64 0, i64 0
  %t161 = call i32 @strcmp(ptr %t159, ptr %t160)
  %t162 = icmp eq i32 %t161, 0
  br i1 %t162, label %cond.then20.0, label %cond.end20
cond.then20.0:
  %t163 = load ptr, ptr %n.addr, align 8
  %t164 = load ptr, ptr %scope.addr, align 8
  %t165 = call ptr @emit-addr-of(ptr %t163, ptr %t164)
  ret ptr %t165
cond.end20:
  %t166 = load ptr, ptr %h.addr.20, align 8
  %t167 = getelementptr inbounds [13 x i8], ptr @.str.290, i64 0, i64 0
  %t168 = call i32 @strcmp(ptr %t166, ptr %t167)
  %t169 = icmp eq i32 %t168, 0
  br i1 %t169, label %cond.then21.0, label %cond.end21
cond.then21.0:
  %t170 = load ptr, ptr %n.addr, align 8
  %t171 = load ptr, ptr %scope.addr, align 8
  %t172 = call ptr @emit-funcall-void(ptr %t170, ptr %t171)
  ret ptr %t172
cond.end21:
  %t173 = load ptr, ptr %h.addr.20, align 8
  %t174 = getelementptr inbounds [6 x i8], ptr @.str.291, i64 0, i64 0
  %t175 = call i32 @strcmp(ptr %t173, ptr %t174)
  %t176 = icmp eq i32 %t175, 0
  br i1 %t176, label %cond.then22.0, label %cond.end22
cond.then22.0:
  %t177 = load ptr, ptr %n.addr, align 8
  %t178 = load ptr, ptr %scope.addr, align 8
  %t179 = call ptr @emit-deref(ptr %t177, ptr %t178)
  ret ptr %t179
cond.end22:
  %t180 = load ptr, ptr %h.addr.20, align 8
  %t181 = getelementptr inbounds [9 x i8], ptr @.str.292, i64 0, i64 0
  %t182 = call i32 @strcmp(ptr %t180, ptr %t181)
  %t183 = icmp eq i32 %t182, 0
  br i1 %t183, label %cond.then23.0, label %cond.end23
cond.then23.0:
  %t184 = load ptr, ptr %n.addr, align 8
  %t185 = load ptr, ptr %scope.addr, align 8
  %t186 = call ptr @emit-ptr-set(ptr %t184, ptr %t185)
  ret ptr %t186
cond.end23:
  %t187 = load ptr, ptr %h.addr.20, align 8
  %t188 = getelementptr inbounds [5 x i8], ptr @.str.293, i64 0, i64 0
  %t189 = call i32 @strcmp(ptr %t187, ptr %t188)
  %t190 = icmp eq i32 %t189, 0
  br i1 %t190, label %cond.then24.0, label %cond.end24
cond.then24.0:
  %t191 = load ptr, ptr %n.addr, align 8
  %t192 = load ptr, ptr %scope.addr, align 8
  %t193 = call ptr @emit-ptr-add(ptr %t191, ptr %t192)
  ret ptr %t193
cond.end24:
  %t194 = load ptr, ptr %h.addr.20, align 8
  %t195 = getelementptr inbounds [2 x i8], ptr @.str.294, i64 0, i64 0
  %t196 = call i32 @strcmp(ptr %t194, ptr %t195)
  %t197 = icmp eq i32 %t196, 0
  br i1 %t197, label %cond.then25.0, label %cond.end25
cond.then25.0:
  %t198 = load ptr, ptr %n.addr, align 8
  %t199 = load ptr, ptr %scope.addr, align 8
  %t200 = call ptr @emit-field-get(ptr %t198, ptr %t199)
  ret ptr %t200
cond.end25:
  %t201 = load ptr, ptr %h.addr.20, align 8
  %t202 = getelementptr inbounds [6 x i8], ptr @.str.295, i64 0, i64 0
  %t203 = call i32 @strcmp(ptr %t201, ptr %t202)
  %t204 = icmp eq i32 %t203, 0
  br i1 %t204, label %cond.then26.0, label %cond.end26
cond.then26.0:
  %t205 = load ptr, ptr %n.addr, align 8
  %t206 = load ptr, ptr %scope.addr, align 8
  %t207 = call ptr @emit-field-set(ptr %t205, ptr %t206)
  ret ptr %t207
cond.end26:
  %t208 = load ptr, ptr %h.addr.20, align 8
  %t209 = getelementptr inbounds [7 x i8], ptr @.str.296, i64 0, i64 0
  %t210 = call i32 @strcmp(ptr %t208, ptr %t209)
  %t211 = icmp eq i32 %t210, 0
  br i1 %t211, label %cond.then27.0, label %cond.end27
cond.then27.0:
  %t212 = load ptr, ptr %n.addr, align 8
  %t213 = load ptr, ptr %scope.addr, align 8
  %t214 = call ptr @emit-sizeof(ptr %t212, ptr %t213)
  ret ptr %t214
cond.end27:
  %t215 = load ptr, ptr %h.addr.20, align 8
  %t216 = getelementptr inbounds [7 x i8], ptr @.str.297, i64 0, i64 0
  %t217 = call i32 @strcmp(ptr %t215, ptr %t216)
  %t218 = icmp eq i32 %t217, 0
  br i1 %t218, label %cond.then28.0, label %cond.end28
cond.then28.0:
  %t219 = load ptr, ptr %n.addr, align 8
  %t220 = load ptr, ptr %scope.addr, align 8
  %t221 = call ptr @emit-alloca-form(ptr %t219, ptr %t220)
  ret ptr %t221
cond.end28:
  %t222 = load ptr, ptr %h.addr.20, align 8
  %t223 = getelementptr inbounds [5 x i8], ptr @.str.298, i64 0, i64 0
  %t224 = call i32 @strcmp(ptr %t222, ptr %t223)
  %t225 = icmp eq i32 %t224, 0
  br i1 %t225, label %cond.then29.0, label %cond.end29
cond.then29.0:
  %t226 = load ptr, ptr %n.addr, align 8
  %t227 = load ptr, ptr %scope.addr, align 8
  %t228 = call ptr @emit-char(ptr %t226, ptr %t227)
  ret ptr %t228
cond.end29:
  %t229 = load ptr, ptr %h.addr.20, align 8
  %t230 = getelementptr inbounds [5 x i8], ptr @.str.299, i64 0, i64 0
  %t231 = call i32 @strcmp(ptr %t229, ptr %t230)
  %t232 = icmp eq i32 %t231, 0
  br i1 %t232, label %cond.then30.0, label %cond.end30
cond.then30.0:
  %t233 = load ptr, ptr %n.addr, align 8
  %t234 = load ptr, ptr %scope.addr, align 8
  %t235 = call ptr @emit-aref(ptr %t233, ptr %t234)
  ret ptr %t235
cond.end30:
  %t236 = load ptr, ptr %h.addr.20, align 8
  %t237 = getelementptr inbounds [6 x i8], ptr @.str.300, i64 0, i64 0
  %t238 = call i32 @strcmp(ptr %t236, ptr %t237)
  %t239 = icmp eq i32 %t238, 0
  br i1 %t239, label %cond.then31.0, label %cond.end31
cond.then31.0:
  %t240 = load ptr, ptr %n.addr, align 8
  %t241 = load ptr, ptr %scope.addr, align 8
  %t242 = call ptr @emit-aset(ptr %t240, ptr %t241)
  ret ptr %t242
cond.end31:
  %t244 = load ptr, ptr %h.addr.20, align 8
  %t245 = call ptr @lookup-binop(ptr %t244)
  store ptr %t245, ptr %op.addr.243, align 8
  %t246 = load ptr, ptr %op.addr.243, align 8
  %t247 = icmp ne ptr %t246, null
  br i1 %t247, label %cond.then32.0, label %cond.end32
cond.then32.0:
  %t248 = load ptr, ptr %n.addr, align 8
  %t249 = load ptr, ptr %scope.addr, align 8
  %t250 = load ptr, ptr %op.addr.243, align 8
  %t251 = call ptr @emit-binop(ptr %t248, ptr %t249, ptr %t250)
  ret ptr %t251
cond.end32:
  %t253 = load ptr, ptr %scope.addr, align 8
  %t254 = load ptr, ptr %h.addr.20, align 8
  %t255 = call ptr @scope-lookup(ptr %t253, ptr %t254)
  store ptr %t255, ptr %sym.addr.252, align 8
  %t256 = load ptr, ptr %sym.addr.252, align 8
  %t257 = icmp eq ptr %t256, null
  br i1 %t257, label %cond.then33.0, label %cond.end33
cond.then33.0:
  %t258 = load ptr, ptr %head.addr.9, align 8
  %t259 = getelementptr inbounds %Node, ptr %t258, i32 0, i32 1
  %t260 = load i32, ptr %t259, align 4
  %t261 = getelementptr inbounds [12 x i8], ptr @.str.301, i64 0, i64 0
  %t262 = load ptr, ptr %h.addr.20, align 8
  %t263 = call ptr @fmt-s(ptr %t261, ptr %t262)
  call void @die-at(i32 %t260, ptr %t263)
  br label %cond.end33
cond.end33:
  %t264 = load ptr, ptr %n.addr, align 8
  %t265 = load ptr, ptr %scope.addr, align 8
  %t266 = load ptr, ptr %sym.addr.252, align 8
  %t267 = call ptr @emit-call(ptr %t264, ptr %t265, ptr %t266)
  ret ptr %t267
}

define void @emit-defvar(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %or.val1 = alloca i1, align 1
  %name-node.addr.13 = alloca ptr, align 8
  %name.addr.24 = alloca ptr, align 8
  %type-name.addr.25 = alloca ptr, align 8
  %ty.addr.37 = alloca ptr, align 8
  %ir-name.addr.43 = alloca ptr, align 8
  %align.addr.47 = alloca i32, align 4
  %init.addr.53 = alloca ptr, align 8
  %zero.addr.74 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp slt i32 %t3, 2
  store i1 %t4, ptr %or.val1, align 1
  br i1 %t4, label %or.end1, label %or.rhs1
or.rhs1:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = call i32 @node-len(ptr %t5)
  %t7 = icmp sgt i32 %t6, 3
  store i1 %t7, ptr %or.val1, align 1
  br label %or.end1
or.end1:
  %t8 = load i1, ptr %or.val1, align 1
  br i1 %t8, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t9 = load ptr, ptr %cc.addr.0, align 8
  %t10 = getelementptr inbounds %Node, ptr %t9, i32 0, i32 1
  %t11 = load i32, ptr %t10, align 4
  %t12 = getelementptr inbounds [39 x i8], ptr @.str.302, i64 0, i64 0
  call void @die-at(i32 %t11, ptr %t12)
  br label %cond.end0
cond.end0:
  %t14 = load ptr, ptr %cc.addr.0, align 8
  %t15 = call ptr @node-at(ptr %t14, i32 1)
  store ptr %t15, ptr %name-node.addr.13, align 8
  %t16 = load ptr, ptr %name-node.addr.13, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp ne i32 %t18, 2
  br i1 %t19, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t20 = load ptr, ptr %name-node.addr.13, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 1
  %t22 = load i32, ptr %t21, align 4
  %t23 = getelementptr inbounds [28 x i8], ptr @.str.303, i64 0, i64 0
  call void @die-at(i32 %t22, ptr %t23)
  br label %cond.end2
cond.end2:
  store ptr null, ptr %name.addr.24, align 8
  store ptr null, ptr %type-name.addr.25, align 8
  %t26 = load ptr, ptr %name-node.addr.13, align 8
  %t27 = getelementptr inbounds %Node, ptr %t26, i32 0, i32 3
  %t28 = load ptr, ptr %t27, align 8
  call void @split-typed(ptr %t28, ptr %name.addr.24, ptr %type-name.addr.25)
  %t29 = load ptr, ptr %type-name.addr.25, align 8
  %t30 = icmp eq ptr %t29, null
  br i1 %t30, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t31 = load ptr, ptr %name-node.addr.13, align 8
  %t32 = getelementptr inbounds %Node, ptr %t31, i32 0, i32 1
  %t33 = load i32, ptr %t32, align 4
  %t34 = getelementptr inbounds [30 x i8], ptr @.str.304, i64 0, i64 0
  %t35 = load ptr, ptr %name.addr.24, align 8
  %t36 = call ptr @fmt-s(ptr %t34, ptr %t35)
  call void @die-at(i32 %t33, ptr %t36)
  br label %cond.end3
cond.end3:
  %t38 = load ptr, ptr %type-name.addr.25, align 8
  %t39 = load ptr, ptr %name-node.addr.13, align 8
  %t40 = getelementptr inbounds %Node, ptr %t39, i32 0, i32 1
  %t41 = load i32, ptr %t40, align 4
  %t42 = call ptr @parse-type-name(ptr %t38, i32 %t41)
  store ptr %t42, ptr %ty.addr.37, align 8
  %t44 = getelementptr inbounds [4 x i8], ptr @.str.305, i64 0, i64 0
  %t45 = load ptr, ptr %name.addr.24, align 8
  %t46 = call ptr @fmt-s(ptr %t44, ptr %t45)
  store ptr %t46, ptr %ir-name.addr.43, align 8
  %t48 = load ptr, ptr %ty.addr.37, align 8
  %t49 = call i32 @type-size(ptr %t48)
  store i32 %t49, ptr %align.addr.47, align 4
  %t50 = load ptr, ptr %cc.addr.0, align 8
  %t51 = call i32 @node-len(ptr %t50)
  %t52 = icmp eq i32 %t51, 3
  br i1 %t52, label %cond.then4.0, label %cond.test4.1
cond.then4.0:
  %t54 = load ptr, ptr %cc.addr.0, align 8
  %t55 = call ptr @node-at(ptr %t54, i32 2)
  store ptr %t55, ptr %init.addr.53, align 8
  %t56 = load ptr, ptr %init.addr.53, align 8
  %t57 = getelementptr inbounds %Node, ptr %t56, i32 0, i32 0
  %t58 = load i32, ptr %t57, align 4
  %t59 = icmp ne i32 %t58, 0
  br i1 %t59, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t60 = load ptr, ptr %init.addr.53, align 8
  %t61 = getelementptr inbounds %Node, ptr %t60, i32 0, i32 1
  %t62 = load i32, ptr %t61, align 4
  %t63 = getelementptr inbounds [37 x i8], ptr @.str.306, i64 0, i64 0
  call void @die-at(i32 %t62, ptr %t63)
  br label %cond.end5
cond.end5:
  %t64 = load ptr, ptr @g-out, align 8
  %t65 = getelementptr inbounds [31 x i8], ptr @.str.307, i64 0, i64 0
  %t66 = load ptr, ptr %ir-name.addr.43, align 8
  %t67 = load ptr, ptr %ty.addr.37, align 8
  %t68 = call ptr @type-to-ir(ptr %t67)
  %t69 = load ptr, ptr %init.addr.53, align 8
  %t70 = getelementptr inbounds %Node, ptr %t69, i32 0, i32 2
  %t71 = load i64, ptr %t70, align 8
  %t72 = load i32, ptr %align.addr.47, align 4
  %t73 = call i32 (ptr, ptr, ...) @fprintf(ptr %t64, ptr %t65, ptr %t66, ptr %t68, i64 %t71, i32 %t72)
  br label %cond.end4
cond.test4.1:
  br i1 1, label %cond.then4.1, label %cond.end4
cond.then4.1:
  %t75 = getelementptr inbounds [2 x i8], ptr @.str.308, i64 0, i64 0
  store ptr %t75, ptr %zero.addr.74, align 8
  %t76 = load ptr, ptr %ty.addr.37, align 8
  %t77 = getelementptr inbounds %Type, ptr %t76, i32 0, i32 0
  %t78 = load i32, ptr %t77, align 4
  %t79 = icmp eq i32 %t78, 6
  br i1 %t79, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t80 = getelementptr inbounds [5 x i8], ptr @.str.309, i64 0, i64 0
  store ptr %t80, ptr %zero.addr.74, align 8
  br label %cond.end6
cond.end6:
  %t81 = load ptr, ptr @g-out, align 8
  %t82 = getelementptr inbounds [30 x i8], ptr @.str.310, i64 0, i64 0
  %t83 = load ptr, ptr %ir-name.addr.43, align 8
  %t84 = load ptr, ptr %ty.addr.37, align 8
  %t85 = call ptr @type-to-ir(ptr %t84)
  %t86 = load ptr, ptr %zero.addr.74, align 8
  %t87 = load i32, ptr %align.addr.47, align 4
  %t88 = call i32 (ptr, ptr, ...) @fprintf(ptr %t81, ptr %t82, ptr %t83, ptr %t85, ptr %t86, i32 %t87)
  br label %cond.end4
cond.end4:
  %t89 = load ptr, ptr @g-globals, align 8
  %t90 = load ptr, ptr %name.addr.24, align 8
  %t91 = load ptr, ptr %ty.addr.37, align 8
  %t92 = load ptr, ptr %ir-name.addr.43, align 8
  %t93 = call ptr @scope-define(ptr %t89, ptr %t90, ptr %t91, ptr %t92, i32 1)
  ret void
}

define void @emit-defconst(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %name.addr.9 = alloca ptr, align 8
  %val.addr.12 = alloca ptr, align 8
  %sym.addr.31 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 3
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [33 x i8], ptr @.str.311, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %name.addr.9, align 8
  %t13 = load ptr, ptr %cc.addr.0, align 8
  %t14 = call ptr @node-at(ptr %t13, i32 2)
  store ptr %t14, ptr %val.addr.12, align 8
  %t15 = load ptr, ptr %name.addr.9, align 8
  %t16 = getelementptr inbounds %Node, ptr %t15, i32 0, i32 0
  %t17 = load i32, ptr %t16, align 4
  %t18 = icmp ne i32 %t17, 2
  br i1 %t18, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t19 = load ptr, ptr %name.addr.9, align 8
  %t20 = getelementptr inbounds %Node, ptr %t19, i32 0, i32 1
  %t21 = load i32, ptr %t20, align 4
  %t22 = getelementptr inbounds [30 x i8], ptr @.str.312, i64 0, i64 0
  call void @die-at(i32 %t21, ptr %t22)
  br label %cond.end1
cond.end1:
  %t23 = load ptr, ptr %val.addr.12, align 8
  %t24 = getelementptr inbounds %Node, ptr %t23, i32 0, i32 0
  %t25 = load i32, ptr %t24, align 4
  %t26 = icmp ne i32 %t25, 0
  br i1 %t26, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t27 = load ptr, ptr %val.addr.12, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 1
  %t29 = load i32, ptr %t28, align 4
  %t30 = getelementptr inbounds [40 x i8], ptr @.str.313, i64 0, i64 0
  call void @die-at(i32 %t29, ptr %t30)
  br label %cond.end2
cond.end2:
  %t32 = load ptr, ptr @g-globals, align 8
  %t33 = load ptr, ptr %name.addr.9, align 8
  %t34 = getelementptr inbounds %Node, ptr %t33, i32 0, i32 3
  %t35 = load ptr, ptr %t34, align 8
  %t36 = load ptr, ptr @ty-i32, align 8
  %t37 = call ptr @scope-define(ptr %t32, ptr %t35, ptr %t36, ptr null, i32 0)
  store ptr %t37, ptr %sym.addr.31, align 8
  %t38 = load ptr, ptr %sym.addr.31, align 8
  %t39 = getelementptr inbounds %Sym, ptr %t38, i32 0, i32 4
  store i32 1, ptr %t39, align 4
  %t40 = load ptr, ptr %sym.addr.31, align 8
  %t41 = getelementptr inbounds [4 x i8], ptr @.str.314, i64 0, i64 0
  %t42 = load ptr, ptr %val.addr.12, align 8
  %t43 = getelementptr inbounds %Node, ptr %t42, i32 0, i32 2
  %t44 = load i64, ptr %t43, align 8
  %t45 = call ptr @fmt-i64(ptr %t41, i64 %t44)
  %t46 = getelementptr inbounds %Sym, ptr %t40, i32 0, i32 5
  store ptr %t45, ptr %t46, align 8
  ret void
}

define void @emit-defenum(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %i.addr.9 = alloca i32, align 4
  %name.addr.14 = alloca ptr, align 8
  %sym.addr.26 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp slt i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [22 x i8], ptr @.str.315, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  store i32 2, ptr %i.addr.9, align 4
  br label %while.cond1
while.cond1:
  %t10 = load i32, ptr %i.addr.9, align 4
  %t11 = load ptr, ptr %cc.addr.0, align 8
  %t12 = call i32 @node-len(ptr %t11)
  %t13 = icmp slt i32 %t10, %t12
  br i1 %t13, label %while.body1, label %while.end1
while.body1:
  %t15 = load ptr, ptr %cc.addr.0, align 8
  %t16 = load i32, ptr %i.addr.9, align 4
  %t17 = call ptr @node-at(ptr %t15, i32 %t16)
  store ptr %t17, ptr %name.addr.14, align 8
  %t18 = load ptr, ptr %name.addr.14, align 8
  %t19 = getelementptr inbounds %Node, ptr %t18, i32 0, i32 0
  %t20 = load i32, ptr %t19, align 4
  %t21 = icmp ne i32 %t20, 2
  br i1 %t21, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t22 = load ptr, ptr %name.addr.14, align 8
  %t23 = getelementptr inbounds %Node, ptr %t22, i32 0, i32 1
  %t24 = load i32, ptr %t23, align 4
  %t25 = getelementptr inbounds [30 x i8], ptr @.str.316, i64 0, i64 0
  call void @die-at(i32 %t24, ptr %t25)
  br label %cond.end2
cond.end2:
  %t27 = load ptr, ptr @g-globals, align 8
  %t28 = load ptr, ptr %name.addr.14, align 8
  %t29 = getelementptr inbounds %Node, ptr %t28, i32 0, i32 3
  %t30 = load ptr, ptr %t29, align 8
  %t31 = load ptr, ptr @ty-i32, align 8
  %t32 = call ptr @scope-define(ptr %t27, ptr %t30, ptr %t31, ptr null, i32 0)
  store ptr %t32, ptr %sym.addr.26, align 8
  %t33 = load ptr, ptr %sym.addr.26, align 8
  %t34 = getelementptr inbounds %Sym, ptr %t33, i32 0, i32 4
  store i32 1, ptr %t34, align 4
  %t35 = load ptr, ptr %sym.addr.26, align 8
  %t36 = getelementptr inbounds [3 x i8], ptr @.str.317, i64 0, i64 0
  %t37 = load i32, ptr %i.addr.9, align 4
  %t38 = sub nsw i32 %t37, 2
  %t39 = call ptr @fmt-i32(ptr %t36, i32 %t38)
  %t40 = getelementptr inbounds %Sym, ptr %t35, i32 0, i32 5
  store ptr %t39, ptr %t40, align 8
  %t41 = load i32, ptr %i.addr.9, align 4
  %t42 = add nsw i32 %t41, 1
  store i32 %t42, ptr %i.addr.9, align 4
  br label %while.cond1
while.end1:
  ret void
}

define void @emit-defstruct(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %name-node.addr.9 = alloca ptr, align 8
  %sd.addr.20 = alloca ptr, align 8
  %nfields.addr.25 = alloca i32, align 4
  %i.addr.46 = alloca i32, align 4
  %field.addr.50 = alloca ptr, align 8
  %fname.addr.63 = alloca ptr, align 8
  %ftype-name.addr.64 = alloca ptr, align 8
  %i.addr.102 = alloca i32, align 4
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp slt i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [24 x i8], ptr @.str.318, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %name-node.addr.9, align 8
  %t12 = load ptr, ptr %name-node.addr.9, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp ne i32 %t14, 2
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %name-node.addr.9, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = getelementptr inbounds [31 x i8], ptr @.str.319, i64 0, i64 0
  call void @die-at(i32 %t18, ptr %t19)
  br label %cond.end1
cond.end1:
  %t21 = load ptr, ptr %name-node.addr.9, align 8
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 3
  %t23 = load ptr, ptr %t22, align 8
  %t24 = call ptr @register-struct(ptr %t23)
  store ptr %t24, ptr %sd.addr.20, align 8
  %t26 = load ptr, ptr %cc.addr.0, align 8
  %t27 = call i32 @node-len(ptr %t26)
  %t28 = sub nsw i32 %t27, 2
  store i32 %t28, ptr %nfields.addr.25, align 4
  %t29 = load ptr, ptr %sd.addr.20, align 8
  %t30 = load i32, ptr %nfields.addr.25, align 4
  %t31 = call i64 @i64(i32 %t30)
  %t32 = call i64 @i64(i32 8)
  %t33 = mul nsw i64 %t31, %t32
  %t34 = call ptr @arena-alloc(i64 %t33)
  %t35 = getelementptr inbounds %StructDef, ptr %t29, i32 0, i32 1
  store ptr %t34, ptr %t35, align 8
  %t36 = load ptr, ptr %sd.addr.20, align 8
  %t37 = load i32, ptr %nfields.addr.25, align 4
  %t38 = call i64 @i64(i32 %t37)
  %t39 = call i64 @i64(i32 8)
  %t40 = mul nsw i64 %t38, %t39
  %t41 = call ptr @arena-alloc(i64 %t40)
  %t42 = getelementptr inbounds %StructDef, ptr %t36, i32 0, i32 2
  store ptr %t41, ptr %t42, align 8
  %t43 = load ptr, ptr %sd.addr.20, align 8
  %t44 = load i32, ptr %nfields.addr.25, align 4
  %t45 = getelementptr inbounds %StructDef, ptr %t43, i32 0, i32 3
  store i32 %t44, ptr %t45, align 4
  store i32 0, ptr %i.addr.46, align 4
  br label %while.cond2
while.cond2:
  %t47 = load i32, ptr %i.addr.46, align 4
  %t48 = load i32, ptr %nfields.addr.25, align 4
  %t49 = icmp slt i32 %t47, %t48
  br i1 %t49, label %while.body2, label %while.end2
while.body2:
  %t51 = load ptr, ptr %cc.addr.0, align 8
  %t52 = load i32, ptr %i.addr.46, align 4
  %t53 = add nsw i32 %t52, 2
  %t54 = call ptr @node-at(ptr %t51, i32 %t53)
  store ptr %t54, ptr %field.addr.50, align 8
  %t55 = load ptr, ptr %field.addr.50, align 8
  %t56 = getelementptr inbounds %Node, ptr %t55, i32 0, i32 0
  %t57 = load i32, ptr %t56, align 4
  %t58 = icmp ne i32 %t57, 2
  br i1 %t58, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t59 = load ptr, ptr %field.addr.50, align 8
  %t60 = getelementptr inbounds %Node, ptr %t59, i32 0, i32 1
  %t61 = load i32, ptr %t60, align 4
  %t62 = getelementptr inbounds [38 x i8], ptr @.str.320, i64 0, i64 0
  call void @die-at(i32 %t61, ptr %t62)
  br label %cond.end3
cond.end3:
  store ptr null, ptr %fname.addr.63, align 8
  store ptr null, ptr %ftype-name.addr.64, align 8
  %t65 = load ptr, ptr %field.addr.50, align 8
  %t66 = getelementptr inbounds %Node, ptr %t65, i32 0, i32 3
  %t67 = load ptr, ptr %t66, align 8
  call void @split-typed(ptr %t67, ptr %fname.addr.63, ptr %ftype-name.addr.64)
  %t68 = load ptr, ptr %ftype-name.addr.64, align 8
  %t69 = icmp eq ptr %t68, null
  br i1 %t69, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t70 = load ptr, ptr %field.addr.50, align 8
  %t71 = getelementptr inbounds %Node, ptr %t70, i32 0, i32 1
  %t72 = load i32, ptr %t71, align 4
  %t73 = getelementptr inbounds [36 x i8], ptr @.str.321, i64 0, i64 0
  %t74 = load ptr, ptr %fname.addr.63, align 8
  %t75 = call ptr @fmt-s(ptr %t73, ptr %t74)
  call void @die-at(i32 %t72, ptr %t75)
  br label %cond.end4
cond.end4:
  %t76 = load ptr, ptr %sd.addr.20, align 8
  %t77 = getelementptr inbounds %StructDef, ptr %t76, i32 0, i32 1
  %t78 = load ptr, ptr %t77, align 8
  %t79 = load i32, ptr %i.addr.46, align 4
  %t80 = sext i32 %t79 to i64
  %t81 = load ptr, ptr %fname.addr.63, align 8
  %t82 = getelementptr inbounds ptr, ptr %t78, i64 %t80
  store ptr %t81, ptr %t82, align 8
  %t83 = load ptr, ptr %sd.addr.20, align 8
  %t84 = getelementptr inbounds %StructDef, ptr %t83, i32 0, i32 2
  %t85 = load ptr, ptr %t84, align 8
  %t86 = load i32, ptr %i.addr.46, align 4
  %t87 = sext i32 %t86 to i64
  %t88 = load ptr, ptr %ftype-name.addr.64, align 8
  %t89 = load ptr, ptr %field.addr.50, align 8
  %t90 = getelementptr inbounds %Node, ptr %t89, i32 0, i32 1
  %t91 = load i32, ptr %t90, align 4
  %t92 = call ptr @parse-type-name(ptr %t88, i32 %t91)
  %t93 = getelementptr inbounds ptr, ptr %t85, i64 %t87
  store ptr %t92, ptr %t93, align 8
  %t94 = load i32, ptr %i.addr.46, align 4
  %t95 = add nsw i32 %t94, 1
  store i32 %t95, ptr %i.addr.46, align 4
  br label %while.cond2
while.end2:
  %t96 = load ptr, ptr @g-out, align 8
  %t97 = getelementptr inbounds [15 x i8], ptr @.str.322, i64 0, i64 0
  %t98 = load ptr, ptr %name-node.addr.9, align 8
  %t99 = getelementptr inbounds %Node, ptr %t98, i32 0, i32 3
  %t100 = load ptr, ptr %t99, align 8
  %t101 = call i32 (ptr, ptr, ...) @fprintf(ptr %t96, ptr %t97, ptr %t100)
  store i32 0, ptr %i.addr.102, align 4
  br label %while.cond5
while.cond5:
  %t103 = load i32, ptr %i.addr.102, align 4
  %t104 = load i32, ptr %nfields.addr.25, align 4
  %t105 = icmp slt i32 %t103, %t104
  br i1 %t105, label %while.body5, label %while.end5
while.body5:
  %t106 = load i32, ptr %i.addr.102, align 4
  %t107 = icmp ne i32 %t106, 0
  br i1 %t107, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t108 = load ptr, ptr @g-out, align 8
  %t109 = getelementptr inbounds [3 x i8], ptr @.str.323, i64 0, i64 0
  %t110 = call i32 (ptr, ptr, ...) @fprintf(ptr %t108, ptr %t109)
  br label %cond.end6
cond.end6:
  %t111 = load ptr, ptr @g-out, align 8
  %t112 = getelementptr inbounds [3 x i8], ptr @.str.324, i64 0, i64 0
  %t113 = load ptr, ptr %sd.addr.20, align 8
  %t114 = getelementptr inbounds %StructDef, ptr %t113, i32 0, i32 2
  %t115 = load ptr, ptr %t114, align 8
  %t116 = load i32, ptr %i.addr.102, align 4
  %t117 = sext i32 %t116 to i64
  %t118 = getelementptr inbounds ptr, ptr %t115, i64 %t117
  %t119 = load ptr, ptr %t118, align 8
  %t120 = call ptr @type-to-ir(ptr %t119)
  %t121 = call i32 (ptr, ptr, ...) @fprintf(ptr %t111, ptr %t112, ptr %t120)
  %t122 = load i32, ptr %i.addr.102, align 4
  %t123 = add nsw i32 %t122, 1
  store i32 %t123, ptr %i.addr.102, align 4
  br label %while.cond5
while.end5:
  %t124 = load ptr, ptr @g-out, align 8
  %t125 = getelementptr inbounds [5 x i8], ptr @.str.325, i64 0, i64 0
  %t126 = call i32 (ptr, ptr, ...) @fprintf(ptr %t124, ptr %t125)
  ret void
}

define void @emit-extern(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %or.val1 = alloca i1, align 1
  %arg1.addr.15 = alloca ptr, align 8
  %name.addr.18 = alloca ptr, align 8
  %type-name.addr.19 = alloca ptr, align 8
  %ty.addr.31 = alloca ptr, align 8
  %ir-name.addr.37 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  store i1 %t4, ptr %or.val1, align 1
  br i1 %t4, label %or.end1, label %or.rhs1
or.rhs1:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = call ptr @node-at(ptr %t5, i32 1)
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 0
  %t8 = load i32, ptr %t7, align 4
  %t9 = icmp ne i32 %t8, 2
  store i1 %t9, ptr %or.val1, align 1
  br label %or.end1
or.end1:
  %t10 = load i1, ptr %or.val1, align 1
  br i1 %t10, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t11 = load ptr, ptr %cc.addr.0, align 8
  %t12 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 1
  %t13 = load i32, ptr %t12, align 4
  %t14 = getelementptr inbounds [26 x i8], ptr @.str.326, i64 0, i64 0
  call void @die-at(i32 %t13, ptr %t14)
  br label %cond.end0
cond.end0:
  %t16 = load ptr, ptr %cc.addr.0, align 8
  %t17 = call ptr @node-at(ptr %t16, i32 1)
  store ptr %t17, ptr %arg1.addr.15, align 8
  store ptr null, ptr %name.addr.18, align 8
  store ptr null, ptr %type-name.addr.19, align 8
  %t20 = load ptr, ptr %arg1.addr.15, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 3
  %t22 = load ptr, ptr %t21, align 8
  call void @split-typed(ptr %t22, ptr %name.addr.18, ptr %type-name.addr.19)
  %t23 = load ptr, ptr %type-name.addr.19, align 8
  %t24 = icmp eq ptr %t23, null
  br i1 %t24, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t25 = load ptr, ptr %arg1.addr.15, align 8
  %t26 = getelementptr inbounds %Node, ptr %t25, i32 0, i32 1
  %t27 = load i32, ptr %t26, align 4
  %t28 = getelementptr inbounds [30 x i8], ptr @.str.327, i64 0, i64 0
  %t29 = load ptr, ptr %name.addr.18, align 8
  %t30 = call ptr @fmt-s(ptr %t28, ptr %t29)
  call void @die-at(i32 %t27, ptr %t30)
  br label %cond.end2
cond.end2:
  %t32 = load ptr, ptr %type-name.addr.19, align 8
  %t33 = load ptr, ptr %arg1.addr.15, align 8
  %t34 = getelementptr inbounds %Node, ptr %t33, i32 0, i32 1
  %t35 = load i32, ptr %t34, align 4
  %t36 = call ptr @parse-type-name(ptr %t32, i32 %t35)
  store ptr %t36, ptr %ty.addr.31, align 8
  %t38 = getelementptr inbounds [4 x i8], ptr @.str.328, i64 0, i64 0
  %t39 = load ptr, ptr %name.addr.18, align 8
  %t40 = call ptr @fmt-s(ptr %t38, ptr %t39)
  store ptr %t40, ptr %ir-name.addr.37, align 8
  %t41 = load ptr, ptr @g-out, align 8
  %t42 = getelementptr inbounds [26 x i8], ptr @.str.329, i64 0, i64 0
  %t43 = load ptr, ptr %ir-name.addr.37, align 8
  %t44 = load ptr, ptr %ty.addr.31, align 8
  %t45 = call ptr @type-to-ir(ptr %t44)
  %t46 = call i32 (ptr, ptr, ...) @fprintf(ptr %t41, ptr %t42, ptr %t43, ptr %t45)
  %t47 = load ptr, ptr @g-globals, align 8
  %t48 = load ptr, ptr %name.addr.18, align 8
  %t49 = load ptr, ptr %ty.addr.31, align 8
  %t50 = load ptr, ptr %ir-name.addr.37, align 8
  %t51 = call ptr @scope-define(ptr %t47, ptr %t48, ptr %t49, ptr %t50, i32 1)
  ret void
}

define void @add-libc(ptr %module.arg, ptr %name.arg, i32 %ret.arg, i32 %p0.arg, i32 %p1.arg, i32 %p2.arg, i32 %p3.arg, i32 %np.arg, i32 %va.arg) {
entry:
  %module.addr = alloca ptr, align 8
  store ptr %module.arg, ptr %module.addr, align 8
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %ret.addr = alloca i32, align 4
  store i32 %ret.arg, ptr %ret.addr, align 4
  %p0.addr = alloca i32, align 4
  store i32 %p0.arg, ptr %p0.addr, align 4
  %p1.addr = alloca i32, align 4
  store i32 %p1.arg, ptr %p1.addr, align 4
  %p2.addr = alloca i32, align 4
  store i32 %p2.arg, ptr %p2.addr, align 4
  %p3.addr = alloca i32, align 4
  store i32 %p3.arg, ptr %p3.addr, align 4
  %np.addr = alloca i32, align 4
  store i32 %np.arg, ptr %np.addr, align 4
  %va.addr = alloca i32, align 4
  store i32 %va.arg, ptr %va.addr, align 4
  %d.addr.0 = alloca ptr, align 8
  %t1 = load ptr, ptr @g-libc, align 8
  %t2 = load i32, ptr @g-num-libc, align 4
  %t3 = sext i32 %t2 to i64
  %t4 = getelementptr inbounds %LibcDecl, ptr %t1, i64 %t3
  store ptr %t4, ptr %d.addr.0, align 8
  %t5 = load ptr, ptr %d.addr.0, align 8
  %t6 = load ptr, ptr %module.addr, align 8
  %t7 = getelementptr inbounds %LibcDecl, ptr %t5, i32 0, i32 0
  store ptr %t6, ptr %t7, align 8
  %t8 = load ptr, ptr %d.addr.0, align 8
  %t9 = load ptr, ptr %name.addr, align 8
  %t10 = getelementptr inbounds %LibcDecl, ptr %t8, i32 0, i32 1
  store ptr %t9, ptr %t10, align 8
  %t11 = load ptr, ptr %d.addr.0, align 8
  %t12 = load i32, ptr %ret.addr, align 4
  %t13 = getelementptr inbounds %LibcDecl, ptr %t11, i32 0, i32 2
  store i32 %t12, ptr %t13, align 4
  %t14 = load ptr, ptr %d.addr.0, align 8
  %t15 = load i32, ptr %p0.addr, align 4
  %t16 = getelementptr inbounds %LibcDecl, ptr %t14, i32 0, i32 3
  store i32 %t15, ptr %t16, align 4
  %t17 = load ptr, ptr %d.addr.0, align 8
  %t18 = load i32, ptr %p1.addr, align 4
  %t19 = getelementptr inbounds %LibcDecl, ptr %t17, i32 0, i32 4
  store i32 %t18, ptr %t19, align 4
  %t20 = load ptr, ptr %d.addr.0, align 8
  %t21 = load i32, ptr %p2.addr, align 4
  %t22 = getelementptr inbounds %LibcDecl, ptr %t20, i32 0, i32 5
  store i32 %t21, ptr %t22, align 4
  %t23 = load ptr, ptr %d.addr.0, align 8
  %t24 = load i32, ptr %p3.addr, align 4
  %t25 = getelementptr inbounds %LibcDecl, ptr %t23, i32 0, i32 6
  store i32 %t24, ptr %t25, align 4
  %t26 = load ptr, ptr %d.addr.0, align 8
  %t27 = load i32, ptr %np.addr, align 4
  %t28 = getelementptr inbounds %LibcDecl, ptr %t26, i32 0, i32 7
  store i32 %t27, ptr %t28, align 4
  %t29 = load ptr, ptr %d.addr.0, align 8
  %t30 = load i32, ptr %va.addr, align 4
  %t31 = getelementptr inbounds %LibcDecl, ptr %t29, i32 0, i32 8
  store i32 %t30, ptr %t31, align 4
  %t32 = load i32, ptr @g-num-libc, align 4
  %t33 = add nsw i32 %t32, 1
  store i32 %t33, ptr @g-num-libc, align 4
  ret void
}

define ptr @kind-to-type(i32 %k.arg) {
entry:
  %k.addr = alloca i32, align 4
  store i32 %k.arg, ptr %k.addr, align 4
  %t0 = load i32, ptr %k.addr, align 4
  %t1 = icmp eq i32 %t0, 0
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t2 = load ptr, ptr @ty-void, align 8
  ret ptr %t2
cond.end0:
  %t3 = load i32, ptr %k.addr, align 4
  %t4 = icmp eq i32 %t3, 2
  br i1 %t4, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t5 = load ptr, ptr @ty-i8, align 8
  ret ptr %t5
cond.end1:
  %t6 = load i32, ptr %k.addr, align 4
  %t7 = icmp eq i32 %t6, 4
  br i1 %t7, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t8 = load ptr, ptr @ty-i32, align 8
  ret ptr %t8
cond.end2:
  %t9 = load i32, ptr %k.addr, align 4
  %t10 = icmp eq i32 %t9, 5
  br i1 %t10, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t11 = load ptr, ptr @ty-i64, align 8
  ret ptr %t11
cond.end3:
  %t12 = load i32, ptr %k.addr, align 4
  %t13 = icmp eq i32 %t12, 6
  br i1 %t13, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t14 = load ptr, ptr @ty-ptr, align 8
  ret ptr %t14
cond.end4:
  %t15 = load ptr, ptr @ty-void, align 8
  ret ptr %t15
}

define i32 @libc-param-kind(ptr %d.arg, i32 %idx.arg) {
entry:
  %d.addr = alloca ptr, align 8
  store ptr %d.arg, ptr %d.addr, align 8
  %idx.addr = alloca i32, align 4
  store i32 %idx.arg, ptr %idx.addr, align 4
  %dd.addr.0 = alloca ptr, align 8
  %t1 = load ptr, ptr %d.addr, align 8
  store ptr %t1, ptr %dd.addr.0, align 8
  %t2 = load i32, ptr %idx.addr, align 4
  %t3 = icmp eq i32 %t2, 0
  br i1 %t3, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t4 = load ptr, ptr %dd.addr.0, align 8
  %t5 = getelementptr inbounds %LibcDecl, ptr %t4, i32 0, i32 3
  %t6 = load i32, ptr %t5, align 4
  ret i32 %t6
cond.end0:
  %t7 = load i32, ptr %idx.addr, align 4
  %t8 = icmp eq i32 %t7, 1
  br i1 %t8, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t9 = load ptr, ptr %dd.addr.0, align 8
  %t10 = getelementptr inbounds %LibcDecl, ptr %t9, i32 0, i32 4
  %t11 = load i32, ptr %t10, align 4
  ret i32 %t11
cond.end1:
  %t12 = load i32, ptr %idx.addr, align 4
  %t13 = icmp eq i32 %t12, 2
  br i1 %t13, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t14 = load ptr, ptr %dd.addr.0, align 8
  %t15 = getelementptr inbounds %LibcDecl, ptr %t14, i32 0, i32 5
  %t16 = load i32, ptr %t15, align 4
  ret i32 %t16
cond.end2:
  %t17 = load i32, ptr %idx.addr, align 4
  %t18 = icmp eq i32 %t17, 3
  br i1 %t18, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t19 = load ptr, ptr %dd.addr.0, align 8
  %t20 = getelementptr inbounds %LibcDecl, ptr %t19, i32 0, i32 6
  %t21 = load i32, ptr %t20, align 4
  ret i32 %t21
cond.end3:
  ret i32 0
}

define void @init-libc() {
entry:
  %t0 = sext i32 80 to i64
  %t1 = getelementptr %LibcDecl, ptr null, i32 1
  %t2 = ptrtoint ptr %t1 to i64
  %t3 = mul nsw i64 %t0, %t2
  %t4 = call ptr @arena-alloc(i64 %t3)
  store ptr %t4, ptr @g-libc, align 8
  %t5 = getelementptr inbounds [6 x i8], ptr @.str.330, i64 0, i64 0
  %t6 = getelementptr inbounds [7 x i8], ptr @.str.331, i64 0, i64 0
  call void @add-libc(ptr %t5, ptr %t6, i32 4, i32 6, i32 0, i32 0, i32 0, i32 1, i32 1)
  %t7 = getelementptr inbounds [6 x i8], ptr @.str.332, i64 0, i64 0
  %t8 = getelementptr inbounds [8 x i8], ptr @.str.333, i64 0, i64 0
  call void @add-libc(ptr %t7, ptr %t8, i32 4, i32 6, i32 6, i32 0, i32 0, i32 2, i32 1)
  %t9 = getelementptr inbounds [6 x i8], ptr @.str.334, i64 0, i64 0
  %t10 = getelementptr inbounds [9 x i8], ptr @.str.335, i64 0, i64 0
  call void @add-libc(ptr %t9, ptr %t10, i32 4, i32 6, i32 5, i32 6, i32 0, i32 3, i32 1)
  %t11 = getelementptr inbounds [6 x i8], ptr @.str.336, i64 0, i64 0
  %t12 = getelementptr inbounds [6 x i8], ptr @.str.337, i64 0, i64 0
  call void @add-libc(ptr %t11, ptr %t12, i32 4, i32 4, i32 6, i32 0, i32 0, i32 2, i32 0)
  %t13 = getelementptr inbounds [6 x i8], ptr @.str.338, i64 0, i64 0
  %t14 = getelementptr inbounds [6 x i8], ptr @.str.339, i64 0, i64 0
  call void @add-libc(ptr %t13, ptr %t14, i32 4, i32 6, i32 6, i32 0, i32 0, i32 2, i32 0)
  %t15 = getelementptr inbounds [6 x i8], ptr @.str.340, i64 0, i64 0
  %t16 = getelementptr inbounds [6 x i8], ptr @.str.341, i64 0, i64 0
  call void @add-libc(ptr %t15, ptr %t16, i32 6, i32 6, i32 6, i32 0, i32 0, i32 2, i32 0)
  %t17 = getelementptr inbounds [6 x i8], ptr @.str.342, i64 0, i64 0
  %t18 = getelementptr inbounds [7 x i8], ptr @.str.343, i64 0, i64 0
  call void @add-libc(ptr %t17, ptr %t18, i32 4, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t19 = getelementptr inbounds [6 x i8], ptr @.str.344, i64 0, i64 0
  %t20 = getelementptr inbounds [6 x i8], ptr @.str.345, i64 0, i64 0
  call void @add-libc(ptr %t19, ptr %t20, i32 5, i32 6, i32 5, i32 5, i32 6, i32 4, i32 0)
  %t21 = getelementptr inbounds [6 x i8], ptr @.str.346, i64 0, i64 0
  %t22 = getelementptr inbounds [7 x i8], ptr @.str.347, i64 0, i64 0
  call void @add-libc(ptr %t21, ptr %t22, i32 5, i32 6, i32 5, i32 5, i32 6, i32 4, i32 0)
  %t23 = getelementptr inbounds [6 x i8], ptr @.str.348, i64 0, i64 0
  %t24 = getelementptr inbounds [6 x i8], ptr @.str.349, i64 0, i64 0
  call void @add-libc(ptr %t23, ptr %t24, i32 4, i32 6, i32 5, i32 4, i32 0, i32 3, i32 0)
  %t25 = getelementptr inbounds [6 x i8], ptr @.str.350, i64 0, i64 0
  %t26 = getelementptr inbounds [6 x i8], ptr @.str.351, i64 0, i64 0
  call void @add-libc(ptr %t25, ptr %t26, i32 5, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t27 = getelementptr inbounds [6 x i8], ptr @.str.352, i64 0, i64 0
  %t28 = getelementptr inbounds [7 x i8], ptr @.str.353, i64 0, i64 0
  call void @add-libc(ptr %t27, ptr %t28, i32 0, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t29 = getelementptr inbounds [6 x i8], ptr @.str.354, i64 0, i64 0
  %t30 = getelementptr inbounds [7 x i8], ptr @.str.355, i64 0, i64 0
  call void @add-libc(ptr %t29, ptr %t30, i32 0, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t31 = getelementptr inbounds [6 x i8], ptr @.str.356, i64 0, i64 0
  %t32 = getelementptr inbounds [15 x i8], ptr @.str.357, i64 0, i64 0
  call void @add-libc(ptr %t31, ptr %t32, i32 6, i32 6, i32 6, i32 0, i32 0, i32 2, i32 0)
  %t33 = getelementptr inbounds [6 x i8], ptr @.str.358, i64 0, i64 0
  %t34 = getelementptr inbounds [7 x i8], ptr @.str.359, i64 0, i64 0
  call void @add-libc(ptr %t33, ptr %t34, i32 4, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t35 = getelementptr inbounds [7 x i8], ptr @.str.360, i64 0, i64 0
  %t36 = getelementptr inbounds [7 x i8], ptr @.str.361, i64 0, i64 0
  call void @add-libc(ptr %t35, ptr %t36, i32 6, i32 5, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t37 = getelementptr inbounds [7 x i8], ptr @.str.362, i64 0, i64 0
  %t38 = getelementptr inbounds [8 x i8], ptr @.str.363, i64 0, i64 0
  call void @add-libc(ptr %t37, ptr %t38, i32 6, i32 6, i32 5, i32 0, i32 0, i32 2, i32 0)
  %t39 = getelementptr inbounds [7 x i8], ptr @.str.364, i64 0, i64 0
  %t40 = getelementptr inbounds [5 x i8], ptr @.str.365, i64 0, i64 0
  call void @add-libc(ptr %t39, ptr %t40, i32 0, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t41 = getelementptr inbounds [7 x i8], ptr @.str.366, i64 0, i64 0
  %t42 = getelementptr inbounds [5 x i8], ptr @.str.367, i64 0, i64 0
  call void @add-libc(ptr %t41, ptr %t42, i32 0, i32 4, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t43 = getelementptr inbounds [7 x i8], ptr @.str.368, i64 0, i64 0
  %t44 = getelementptr inbounds [7 x i8], ptr @.str.369, i64 0, i64 0
  call void @add-libc(ptr %t43, ptr %t44, i32 5, i32 6, i32 6, i32 4, i32 0, i32 3, i32 0)
  %t45 = getelementptr inbounds [7 x i8], ptr @.str.370, i64 0, i64 0
  %t46 = getelementptr inbounds [7 x i8], ptr @.str.371, i64 0, i64 0
  call void @add-libc(ptr %t45, ptr %t46, i32 6, i32 6, i32 6, i32 5, i32 0, i32 3, i32 0)
  %t47 = getelementptr inbounds [7 x i8], ptr @.str.372, i64 0, i64 0
  %t48 = getelementptr inbounds [7 x i8], ptr @.str.373, i64 0, i64 0
  call void @add-libc(ptr %t47, ptr %t48, i32 6, i32 6, i32 4, i32 5, i32 0, i32 3, i32 0)
  %t49 = getelementptr inbounds [7 x i8], ptr @.str.374, i64 0, i64 0
  %t50 = getelementptr inbounds [7 x i8], ptr @.str.375, i64 0, i64 0
  call void @add-libc(ptr %t49, ptr %t50, i32 4, i32 6, i32 6, i32 5, i32 0, i32 3, i32 0)
  %t51 = getelementptr inbounds [7 x i8], ptr @.str.376, i64 0, i64 0
  %t52 = getelementptr inbounds [7 x i8], ptr @.str.377, i64 0, i64 0
  call void @add-libc(ptr %t51, ptr %t52, i32 5, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t53 = getelementptr inbounds [7 x i8], ptr @.str.378, i64 0, i64 0
  %t54 = getelementptr inbounds [7 x i8], ptr @.str.379, i64 0, i64 0
  call void @add-libc(ptr %t53, ptr %t54, i32 4, i32 6, i32 6, i32 0, i32 0, i32 2, i32 0)
  %t55 = getelementptr inbounds [7 x i8], ptr @.str.380, i64 0, i64 0
  %t56 = getelementptr inbounds [8 x i8], ptr @.str.381, i64 0, i64 0
  call void @add-libc(ptr %t55, ptr %t56, i32 4, i32 6, i32 6, i32 5, i32 0, i32 3, i32 0)
  %t57 = getelementptr inbounds [7 x i8], ptr @.str.382, i64 0, i64 0
  %t58 = getelementptr inbounds [7 x i8], ptr @.str.383, i64 0, i64 0
  call void @add-libc(ptr %t57, ptr %t58, i32 6, i32 6, i32 4, i32 0, i32 0, i32 2, i32 0)
  %t59 = getelementptr inbounds [7 x i8], ptr @.str.384, i64 0, i64 0
  %t60 = getelementptr inbounds [8 x i8], ptr @.str.385, i64 0, i64 0
  call void @add-libc(ptr %t59, ptr %t60, i32 6, i32 6, i32 5, i32 0, i32 0, i32 2, i32 0)
  %t61 = getelementptr inbounds [6 x i8], ptr @.str.386, i64 0, i64 0
  %t62 = getelementptr inbounds [8 x i8], ptr @.str.387, i64 0, i64 0
  call void @add-libc(ptr %t61, ptr %t62, i32 4, i32 4, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t63 = getelementptr inbounds [6 x i8], ptr @.str.388, i64 0, i64 0
  %t64 = getelementptr inbounds [8 x i8], ptr @.str.389, i64 0, i64 0
  call void @add-libc(ptr %t63, ptr %t64, i32 4, i32 4, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t65 = getelementptr inbounds [7 x i8], ptr @.str.390, i64 0, i64 0
  %t66 = getelementptr inbounds [4 x i8], ptr @.str.391, i64 0, i64 0
  call void @add-libc(ptr %t65, ptr %t66, i32 4, i32 4, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t67 = getelementptr inbounds [7 x i8], ptr @.str.392, i64 0, i64 0
  %t68 = getelementptr inbounds [5 x i8], ptr @.str.393, i64 0, i64 0
  call void @add-libc(ptr %t67, ptr %t68, i32 4, i32 4, i32 4, i32 0, i32 0, i32 2, i32 0)
  %t69 = getelementptr inbounds [7 x i8], ptr @.str.394, i64 0, i64 0
  %t70 = getelementptr inbounds [6 x i8], ptr @.str.395, i64 0, i64 0
  call void @add-libc(ptr %t69, ptr %t70, i32 4, i32 4, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t71 = getelementptr inbounds [5 x i8], ptr @.str.396, i64 0, i64 0
  %t72 = getelementptr inbounds [28 x i8], ptr @.str.397, i64 0, i64 0
  call void @add-libc(ptr %t71, ptr %t72, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0)
  %t73 = getelementptr inbounds [5 x i8], ptr @.str.398, i64 0, i64 0
  %t74 = getelementptr inbounds [24 x i8], ptr @.str.399, i64 0, i64 0
  call void @add-libc(ptr %t73, ptr %t74, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0)
  %t75 = getelementptr inbounds [5 x i8], ptr @.str.400, i64 0, i64 0
  %t76 = getelementptr inbounds [26 x i8], ptr @.str.401, i64 0, i64 0
  call void @add-libc(ptr %t75, ptr %t76, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0)
  %t77 = getelementptr inbounds [5 x i8], ptr @.str.402, i64 0, i64 0
  %t78 = getelementptr inbounds [28 x i8], ptr @.str.403, i64 0, i64 0
  call void @add-libc(ptr %t77, ptr %t78, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0)
  %t79 = getelementptr inbounds [5 x i8], ptr @.str.404, i64 0, i64 0
  %t80 = getelementptr inbounds [19 x i8], ptr @.str.405, i64 0, i64 0
  call void @add-libc(ptr %t79, ptr %t80, i32 6, i32 6, i32 6, i32 0, i32 0, i32 2, i32 0)
  %t81 = getelementptr inbounds [5 x i8], ptr @.str.406, i64 0, i64 0
  %t82 = getelementptr inbounds [28 x i8], ptr @.str.407, i64 0, i64 0
  call void @add-libc(ptr %t81, ptr %t82, i32 6, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t83 = getelementptr inbounds [5 x i8], ptr @.str.408, i64 0, i64 0
  %t84 = getelementptr inbounds [28 x i8], ptr @.str.409, i64 0, i64 0
  call void @add-libc(ptr %t83, ptr %t84, i32 2, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t85 = getelementptr inbounds [5 x i8], ptr @.str.410, i64 0, i64 0
  %t86 = getelementptr inbounds [53 x i8], ptr @.str.411, i64 0, i64 0
  call void @add-libc(ptr %t85, ptr %t86, i32 6, i32 6, i32 2, i32 6, i32 6, i32 4, i32 0)
  %t87 = getelementptr inbounds [5 x i8], ptr @.str.412, i64 0, i64 0
  %t88 = getelementptr inbounds [28 x i8], ptr @.str.413, i64 0, i64 0
  call void @add-libc(ptr %t87, ptr %t88, i32 0, i32 6, i32 6, i32 0, i32 0, i32 2, i32 0)
  %t89 = getelementptr inbounds [5 x i8], ptr @.str.414, i64 0, i64 0
  %t90 = getelementptr inbounds [18 x i8], ptr @.str.415, i64 0, i64 0
  call void @add-libc(ptr %t89, ptr %t90, i32 6, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0)
  %t91 = getelementptr inbounds [5 x i8], ptr @.str.416, i64 0, i64 0
  %t92 = getelementptr inbounds [34 x i8], ptr @.str.417, i64 0, i64 0
  call void @add-libc(ptr %t91, ptr %t92, i32 6, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0)
  %t93 = getelementptr inbounds [5 x i8], ptr @.str.418, i64 0, i64 0
  %t94 = getelementptr inbounds [32 x i8], ptr @.str.419, i64 0, i64 0
  call void @add-libc(ptr %t93, ptr %t94, i32 0, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t95 = getelementptr inbounds [5 x i8], ptr @.str.420, i64 0, i64 0
  %t96 = getelementptr inbounds [33 x i8], ptr @.str.421, i64 0, i64 0
  call void @add-libc(ptr %t95, ptr %t96, i32 6, i32 6, i32 6, i32 0, i32 0, i32 2, i32 0)
  %t97 = getelementptr inbounds [5 x i8], ptr @.str.422, i64 0, i64 0
  %t98 = getelementptr inbounds [42 x i8], ptr @.str.423, i64 0, i64 0
  call void @add-libc(ptr %t97, ptr %t98, i32 6, i32 6, i32 5, i32 6, i32 0, i32 3, i32 0)
  %t99 = getelementptr inbounds [5 x i8], ptr @.str.424, i64 0, i64 0
  %t100 = getelementptr inbounds [21 x i8], ptr @.str.425, i64 0, i64 0
  call void @add-libc(ptr %t99, ptr %t100, i32 4, i32 6, i32 6, i32 6, i32 6, i32 4, i32 0)
  %t101 = getelementptr inbounds [5 x i8], ptr @.str.426, i64 0, i64 0
  %t102 = getelementptr inbounds [28 x i8], ptr @.str.427, i64 0, i64 0
  call void @add-libc(ptr %t101, ptr %t102, i32 6, i32 6, i32 6, i32 6, i32 0, i32 3, i32 0)
  %t103 = getelementptr inbounds [5 x i8], ptr @.str.428, i64 0, i64 0
  %t104 = getelementptr inbounds [19 x i8], ptr @.str.429, i64 0, i64 0
  call void @add-libc(ptr %t103, ptr %t104, i32 6, i32 6, i32 6, i32 6, i32 0, i32 3, i32 0)
  %t105 = getelementptr inbounds [5 x i8], ptr @.str.430, i64 0, i64 0
  %t106 = getelementptr inbounds [20 x i8], ptr @.str.431, i64 0, i64 0
  call void @add-libc(ptr %t105, ptr %t106, i32 6, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t107 = getelementptr inbounds [5 x i8], ptr @.str.432, i64 0, i64 0
  %t108 = getelementptr inbounds [24 x i8], ptr @.str.433, i64 0, i64 0
  call void @add-libc(ptr %t107, ptr %t108, i32 0, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  %t109 = getelementptr inbounds [5 x i8], ptr @.str.434, i64 0, i64 0
  %t110 = getelementptr inbounds [17 x i8], ptr @.str.435, i64 0, i64 0
  call void @add-libc(ptr %t109, ptr %t110, i32 0, i32 6, i32 0, i32 0, i32 0, i32 1, i32 0)
  ret void
}

define void @emit-include(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %or.val1 = alloca i1, align 1
  %mod.addr.15 = alloca ptr, align 8
  %found.addr.20 = alloca i32, align 4
  %i.addr.21 = alloca i32, align 4
  %d.addr.25 = alloca ptr, align 8
  %ft.addr.36 = alloca ptr, align 8
  %j.addr.38 = alloca i32, align 4
  %sep.addr.135 = alloca ptr, align 8
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  store i1 %t4, ptr %or.val1, align 1
  br i1 %t4, label %or.end1, label %or.rhs1
or.rhs1:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = call ptr @node-at(ptr %t5, i32 1)
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 0
  %t8 = load i32, ptr %t7, align 4
  %t9 = icmp ne i32 %t8, 2
  store i1 %t9, ptr %or.val1, align 1
  br label %or.end1
or.end1:
  %t10 = load i1, ptr %or.val1, align 1
  br i1 %t10, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t11 = load ptr, ptr %cc.addr.0, align 8
  %t12 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 1
  %t13 = load i32, ptr %t12, align 4
  %t14 = getelementptr inbounds [28 x i8], ptr @.str.436, i64 0, i64 0
  call void @die-at(i32 %t13, ptr %t14)
  br label %cond.end0
cond.end0:
  %t16 = load ptr, ptr %cc.addr.0, align 8
  %t17 = call ptr @node-at(ptr %t16, i32 1)
  %t18 = getelementptr inbounds %Node, ptr %t17, i32 0, i32 3
  %t19 = load ptr, ptr %t18, align 8
  store ptr %t19, ptr %mod.addr.15, align 8
  store i32 0, ptr %found.addr.20, align 4
  store i32 0, ptr %i.addr.21, align 4
  br label %while.cond2
while.cond2:
  %t22 = load i32, ptr %i.addr.21, align 4
  %t23 = load i32, ptr @g-num-libc, align 4
  %t24 = icmp slt i32 %t22, %t23
  br i1 %t24, label %while.body2, label %while.end2
while.body2:
  %t26 = load ptr, ptr @g-libc, align 8
  %t27 = load i32, ptr %i.addr.21, align 4
  %t28 = sext i32 %t27 to i64
  %t29 = getelementptr inbounds %LibcDecl, ptr %t26, i64 %t28
  store ptr %t29, ptr %d.addr.25, align 8
  %t30 = load ptr, ptr %d.addr.25, align 8
  %t31 = getelementptr inbounds %LibcDecl, ptr %t30, i32 0, i32 0
  %t32 = load ptr, ptr %t31, align 8
  %t33 = load ptr, ptr %mod.addr.15, align 8
  %t34 = call i32 @strcmp(ptr %t32, ptr %t33)
  %t35 = icmp eq i32 %t34, 0
  br i1 %t35, label %cond.then3.0, label %cond.end3
cond.then3.0:
  store i32 1, ptr %found.addr.20, align 4
  %t37 = call ptr @make-type(i32 7)
  store ptr %t37, ptr %ft.addr.36, align 8
  store i32 0, ptr %j.addr.38, align 4
  %t39 = load ptr, ptr %ft.addr.36, align 8
  %t40 = load ptr, ptr %d.addr.25, align 8
  %t41 = getelementptr inbounds %LibcDecl, ptr %t40, i32 0, i32 2
  %t42 = load i32, ptr %t41, align 4
  %t43 = call ptr @kind-to-type(i32 %t42)
  %t44 = getelementptr inbounds %Type, ptr %t39, i32 0, i32 1
  store ptr %t43, ptr %t44, align 8
  %t45 = load ptr, ptr %ft.addr.36, align 8
  %t46 = load ptr, ptr %d.addr.25, align 8
  %t47 = getelementptr inbounds %LibcDecl, ptr %t46, i32 0, i32 7
  %t48 = load i32, ptr %t47, align 4
  %t49 = getelementptr inbounds %Type, ptr %t45, i32 0, i32 3
  store i32 %t48, ptr %t49, align 4
  %t50 = load ptr, ptr %ft.addr.36, align 8
  %t51 = load ptr, ptr %d.addr.25, align 8
  %t52 = getelementptr inbounds %LibcDecl, ptr %t51, i32 0, i32 7
  %t53 = load i32, ptr %t52, align 4
  %t54 = call i64 @i64(i32 %t53)
  %t55 = call i64 @i64(i32 8)
  %t56 = mul nsw i64 %t54, %t55
  %t57 = call ptr @arena-alloc(i64 %t56)
  %t58 = getelementptr inbounds %Type, ptr %t50, i32 0, i32 2
  store ptr %t57, ptr %t58, align 8
  br label %while.cond4
while.cond4:
  %t59 = load i32, ptr %j.addr.38, align 4
  %t60 = load ptr, ptr %d.addr.25, align 8
  %t61 = getelementptr inbounds %LibcDecl, ptr %t60, i32 0, i32 7
  %t62 = load i32, ptr %t61, align 4
  %t63 = icmp slt i32 %t59, %t62
  br i1 %t63, label %while.body4, label %while.end4
while.body4:
  %t64 = load ptr, ptr %ft.addr.36, align 8
  %t65 = getelementptr inbounds %Type, ptr %t64, i32 0, i32 2
  %t66 = load ptr, ptr %t65, align 8
  %t67 = load i32, ptr %j.addr.38, align 4
  %t68 = sext i32 %t67 to i64
  %t69 = load ptr, ptr %d.addr.25, align 8
  %t70 = load i32, ptr %j.addr.38, align 4
  %t71 = call i32 @libc-param-kind(ptr %t69, i32 %t70)
  %t72 = call ptr @kind-to-type(i32 %t71)
  %t73 = getelementptr inbounds ptr, ptr %t66, i64 %t68
  store ptr %t72, ptr %t73, align 8
  %t74 = load i32, ptr %j.addr.38, align 4
  %t75 = add nsw i32 %t74, 1
  store i32 %t75, ptr %j.addr.38, align 4
  br label %while.cond4
while.end4:
  %t76 = load ptr, ptr %ft.addr.36, align 8
  %t77 = load ptr, ptr %d.addr.25, align 8
  %t78 = getelementptr inbounds %LibcDecl, ptr %t77, i32 0, i32 8
  %t79 = load i32, ptr %t78, align 4
  %t80 = getelementptr inbounds %Type, ptr %t76, i32 0, i32 4
  store i32 %t79, ptr %t80, align 4
  %t81 = load ptr, ptr @g-globals, align 8
  %t82 = load ptr, ptr %d.addr.25, align 8
  %t83 = getelementptr inbounds %LibcDecl, ptr %t82, i32 0, i32 1
  %t84 = load ptr, ptr %t83, align 8
  %t85 = load ptr, ptr %ft.addr.36, align 8
  %t86 = getelementptr inbounds [4 x i8], ptr @.str.437, i64 0, i64 0
  %t87 = load ptr, ptr %d.addr.25, align 8
  %t88 = getelementptr inbounds %LibcDecl, ptr %t87, i32 0, i32 1
  %t89 = load ptr, ptr %t88, align 8
  %t90 = call ptr @fmt-s(ptr %t86, ptr %t89)
  %t91 = call ptr @scope-define(ptr %t81, ptr %t84, ptr %t85, ptr %t90, i32 0)
  %t92 = load ptr, ptr %d.addr.25, align 8
  %t93 = getelementptr inbounds %LibcDecl, ptr %t92, i32 0, i32 1
  %t94 = load ptr, ptr %t93, align 8
  %t95 = getelementptr inbounds [7 x i8], ptr @.str.438, i64 0, i64 0
  %t96 = call i32 @strcmp(ptr %t94, ptr %t95)
  %t97 = icmp eq i32 %t96, 0
  br i1 %t97, label %cond.then5.0, label %cond.end5
cond.then5.0:
  store i32 1, ptr @g-malloc-decl-done, align 4
  br label %cond.end5
cond.end5:
  %t98 = load ptr, ptr @g-out, align 8
  %t99 = getelementptr inbounds [16 x i8], ptr @.str.439, i64 0, i64 0
  %t100 = load ptr, ptr %ft.addr.36, align 8
  %t101 = getelementptr inbounds %Type, ptr %t100, i32 0, i32 1
  %t102 = load ptr, ptr %t101, align 8
  %t103 = call ptr @type-to-ir(ptr %t102)
  %t104 = load ptr, ptr %d.addr.25, align 8
  %t105 = getelementptr inbounds %LibcDecl, ptr %t104, i32 0, i32 1
  %t106 = load ptr, ptr %t105, align 8
  %t107 = call i32 (ptr, ptr, ...) @fprintf(ptr %t98, ptr %t99, ptr %t103, ptr %t106)
  store i32 0, ptr %j.addr.38, align 4
  br label %while.cond6
while.cond6:
  %t108 = load i32, ptr %j.addr.38, align 4
  %t109 = load ptr, ptr %d.addr.25, align 8
  %t110 = getelementptr inbounds %LibcDecl, ptr %t109, i32 0, i32 7
  %t111 = load i32, ptr %t110, align 4
  %t112 = icmp slt i32 %t108, %t111
  br i1 %t112, label %while.body6, label %while.end6
while.body6:
  %t113 = load i32, ptr %j.addr.38, align 4
  %t114 = icmp ne i32 %t113, 0
  br i1 %t114, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t115 = load ptr, ptr @g-out, align 8
  %t116 = getelementptr inbounds [3 x i8], ptr @.str.440, i64 0, i64 0
  %t117 = call i32 (ptr, ptr, ...) @fprintf(ptr %t115, ptr %t116)
  br label %cond.end7
cond.end7:
  %t118 = load ptr, ptr @g-out, align 8
  %t119 = getelementptr inbounds [3 x i8], ptr @.str.441, i64 0, i64 0
  %t120 = load ptr, ptr %ft.addr.36, align 8
  %t121 = getelementptr inbounds %Type, ptr %t120, i32 0, i32 2
  %t122 = load ptr, ptr %t121, align 8
  %t123 = load i32, ptr %j.addr.38, align 4
  %t124 = sext i32 %t123 to i64
  %t125 = getelementptr inbounds ptr, ptr %t122, i64 %t124
  %t126 = load ptr, ptr %t125, align 8
  %t127 = call ptr @type-to-ir(ptr %t126)
  %t128 = call i32 (ptr, ptr, ...) @fprintf(ptr %t118, ptr %t119, ptr %t127)
  %t129 = load i32, ptr %j.addr.38, align 4
  %t130 = add nsw i32 %t129, 1
  store i32 %t130, ptr %j.addr.38, align 4
  br label %while.cond6
while.end6:
  %t131 = load ptr, ptr %d.addr.25, align 8
  %t132 = getelementptr inbounds %LibcDecl, ptr %t131, i32 0, i32 8
  %t133 = load i32, ptr %t132, align 4
  %t134 = icmp ne i32 %t133, 0
  br i1 %t134, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t136 = getelementptr inbounds [1 x i8], ptr @.str.442, i64 0, i64 0
  store ptr %t136, ptr %sep.addr.135, align 8
  %t137 = load ptr, ptr %d.addr.25, align 8
  %t138 = getelementptr inbounds %LibcDecl, ptr %t137, i32 0, i32 7
  %t139 = load i32, ptr %t138, align 4
  %t140 = icmp ne i32 %t139, 0
  br i1 %t140, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t141 = getelementptr inbounds [3 x i8], ptr @.str.443, i64 0, i64 0
  store ptr %t141, ptr %sep.addr.135, align 8
  br label %cond.end9
cond.end9:
  %t142 = load ptr, ptr @g-out, align 8
  %t143 = getelementptr inbounds [6 x i8], ptr @.str.444, i64 0, i64 0
  %t144 = load ptr, ptr %sep.addr.135, align 8
  %t145 = call i32 (ptr, ptr, ...) @fprintf(ptr %t142, ptr %t143, ptr %t144)
  br label %cond.end8
cond.end8:
  %t146 = load ptr, ptr @g-out, align 8
  %t147 = getelementptr inbounds [3 x i8], ptr @.str.445, i64 0, i64 0
  %t148 = call i32 (ptr, ptr, ...) @fprintf(ptr %t146, ptr %t147)
  br label %cond.end3
cond.end3:
  %t149 = load i32, ptr %i.addr.21, align 4
  %t150 = add nsw i32 %t149, 1
  store i32 %t150, ptr %i.addr.21, align 4
  br label %while.cond2
while.end2:
  %t151 = load i32, ptr %found.addr.20, align 4
  %t152 = icmp ne i32 %t151, 0
  br i1 %t152, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t153 = load ptr, ptr @g-out, align 8
  %t154 = getelementptr inbounds [2 x i8], ptr @.str.446, i64 0, i64 0
  %t155 = call i32 (ptr, ptr, ...) @fprintf(ptr %t153, ptr %t154)
  br label %cond.end10
cond.end10:
  %t156 = load i32, ptr %found.addr.20, align 4
  %t157 = icmp eq i32 %t156, 0
  br i1 %t157, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t158 = load ptr, ptr %cc.addr.0, align 8
  %t159 = getelementptr inbounds %Node, ptr %t158, i32 0, i32 1
  %t160 = load i32, ptr %t159, align 4
  %t161 = getelementptr inbounds [20 x i8], ptr @.str.447, i64 0, i64 0
  %t162 = load ptr, ptr %mod.addr.15, align 8
  %t163 = call ptr @fmt-s(ptr %t161, ptr %t162)
  call void @die-at(i32 %t160, ptr %t163)
  br label %cond.end11
cond.end11:
  ret void
}

define void @emit-defn(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %name-node.addr.9 = alloca ptr, align 8
  %params-node.addr.12 = alloca ptr, align 8
  %fname.addr.30 = alloca ptr, align 8
  %ret-name.addr.31 = alloca ptr, align 8
  %ret.addr.43 = alloca ptr, align 8
  %nparams.addr.49 = alloca i32, align 4
  %param-types.addr.52 = alloca ptr, align 8
  %param-names.addr.53 = alloca ptr, align 8
  %i.addr.66 = alloca i32, align 4
  %p.addr.70 = alloca ptr, align 8
  %pname.addr.74 = alloca ptr, align 8
  %ptype-name.addr.75 = alloca ptr, align 8
  %ft.addr.111 = alloca ptr, align 8
  %fn-scope.addr.131 = alloca ptr, align 8
  %i.addr.134 = alloca i32, align 4
  %pname.addr.138 = alloca ptr, align 8
  %ptype.addr.144 = alloca ptr, align 8
  %slot.addr.150 = alloca ptr, align 8
  %arg.addr.154 = alloca ptr, align 8
  %palign.addr.158 = alloca i32, align 4
  %zero.addr.203 = alloca ptr, align 8
  %and.val16 = alloca i1, align 1
  %and.val18 = alloca i1, align 1
  %t1 = load ptr, ptr %call.addr, align 8
  store ptr %t1, ptr %cc.addr.0, align 8
  %t2 = load ptr, ptr %cc.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp slt i32 %t3, 4
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %cc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [15 x i8], ptr @.str.448, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %name-node.addr.9, align 8
  %t13 = load ptr, ptr %cc.addr.0, align 8
  %t14 = call ptr @node-at(ptr %t13, i32 2)
  store ptr %t14, ptr %params-node.addr.12, align 8
  %t15 = load ptr, ptr %name-node.addr.9, align 8
  %t16 = getelementptr inbounds %Node, ptr %t15, i32 0, i32 0
  %t17 = load i32, ptr %t16, align 4
  %t18 = icmp ne i32 %t17, 2
  br i1 %t18, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t19 = load ptr, ptr %name-node.addr.9, align 8
  %t20 = getelementptr inbounds %Node, ptr %t19, i32 0, i32 1
  %t21 = load i32, ptr %t20, align 4
  %t22 = getelementptr inbounds [26 x i8], ptr @.str.449, i64 0, i64 0
  call void @die-at(i32 %t21, ptr %t22)
  br label %cond.end1
cond.end1:
  %t23 = load ptr, ptr %params-node.addr.12, align 8
  %t24 = call i32 @node-is-list(ptr %t23)
  %t25 = icmp eq i32 %t24, 0
  br i1 %t25, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t26 = load ptr, ptr %name-node.addr.9, align 8
  %t27 = getelementptr inbounds %Node, ptr %t26, i32 0, i32 1
  %t28 = load i32, ptr %t27, align 4
  %t29 = getelementptr inbounds [26 x i8], ptr @.str.450, i64 0, i64 0
  call void @die-at(i32 %t28, ptr %t29)
  br label %cond.end2
cond.end2:
  store ptr null, ptr %fname.addr.30, align 8
  store ptr null, ptr %ret-name.addr.31, align 8
  %t32 = load ptr, ptr %name-node.addr.9, align 8
  %t33 = getelementptr inbounds %Node, ptr %t32, i32 0, i32 3
  %t34 = load ptr, ptr %t33, align 8
  call void @split-typed(ptr %t34, ptr %fname.addr.30, ptr %ret-name.addr.31)
  %t35 = load ptr, ptr %ret-name.addr.31, align 8
  %t36 = icmp eq ptr %t35, null
  br i1 %t36, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t37 = load ptr, ptr %name-node.addr.9, align 8
  %t38 = getelementptr inbounds %Node, ptr %t37, i32 0, i32 1
  %t39 = load i32, ptr %t38, align 4
  %t40 = getelementptr inbounds [28 x i8], ptr @.str.451, i64 0, i64 0
  %t41 = load ptr, ptr %fname.addr.30, align 8
  %t42 = call ptr @fmt-s(ptr %t40, ptr %t41)
  call void @die-at(i32 %t39, ptr %t42)
  br label %cond.end3
cond.end3:
  %t44 = load ptr, ptr %ret-name.addr.31, align 8
  %t45 = load ptr, ptr %name-node.addr.9, align 8
  %t46 = getelementptr inbounds %Node, ptr %t45, i32 0, i32 1
  %t47 = load i32, ptr %t46, align 4
  %t48 = call ptr @parse-type-name(ptr %t44, i32 %t47)
  store ptr %t48, ptr %ret.addr.43, align 8
  %t50 = load ptr, ptr %params-node.addr.12, align 8
  %t51 = call i32 @node-len(ptr %t50)
  store i32 %t51, ptr %nparams.addr.49, align 4
  store ptr null, ptr %param-types.addr.52, align 8
  store ptr null, ptr %param-names.addr.53, align 8
  %t54 = load i32, ptr %nparams.addr.49, align 4
  %t55 = icmp sgt i32 %t54, 0
  br i1 %t55, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t56 = load i32, ptr %nparams.addr.49, align 4
  %t57 = call i64 @i64(i32 %t56)
  %t58 = call i64 @i64(i32 8)
  %t59 = mul nsw i64 %t57, %t58
  %t60 = call ptr @arena-alloc(i64 %t59)
  store ptr %t60, ptr %param-types.addr.52, align 8
  %t61 = load i32, ptr %nparams.addr.49, align 4
  %t62 = call i64 @i64(i32 %t61)
  %t63 = call i64 @i64(i32 8)
  %t64 = mul nsw i64 %t62, %t63
  %t65 = call ptr @arena-alloc(i64 %t64)
  store ptr %t65, ptr %param-names.addr.53, align 8
  br label %cond.end4
cond.end4:
  store i32 0, ptr %i.addr.66, align 4
  br label %while.cond5
while.cond5:
  %t67 = load i32, ptr %i.addr.66, align 4
  %t68 = load i32, ptr %nparams.addr.49, align 4
  %t69 = icmp slt i32 %t67, %t68
  br i1 %t69, label %while.body5, label %while.end5
while.body5:
  %t71 = load ptr, ptr %params-node.addr.12, align 8
  %t72 = load i32, ptr %i.addr.66, align 4
  %t73 = call ptr @node-at(ptr %t71, i32 %t72)
  store ptr %t73, ptr %p.addr.70, align 8
  store ptr null, ptr %pname.addr.74, align 8
  store ptr null, ptr %ptype-name.addr.75, align 8
  %t76 = load ptr, ptr %p.addr.70, align 8
  %t77 = getelementptr inbounds %Node, ptr %t76, i32 0, i32 0
  %t78 = load i32, ptr %t77, align 4
  %t79 = icmp ne i32 %t78, 2
  br i1 %t79, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t80 = load ptr, ptr %p.addr.70, align 8
  %t81 = getelementptr inbounds %Node, ptr %t80, i32 0, i32 1
  %t82 = load i32, ptr %t81, align 4
  %t83 = getelementptr inbounds [27 x i8], ptr @.str.452, i64 0, i64 0
  call void @die-at(i32 %t82, ptr %t83)
  br label %cond.end6
cond.end6:
  %t84 = load ptr, ptr %p.addr.70, align 8
  %t85 = getelementptr inbounds %Node, ptr %t84, i32 0, i32 3
  %t86 = load ptr, ptr %t85, align 8
  call void @split-typed(ptr %t86, ptr %pname.addr.74, ptr %ptype-name.addr.75)
  %t87 = load ptr, ptr %ptype-name.addr.75, align 8
  %t88 = icmp eq ptr %t87, null
  br i1 %t88, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t89 = load ptr, ptr %p.addr.70, align 8
  %t90 = getelementptr inbounds %Node, ptr %t89, i32 0, i32 1
  %t91 = load i32, ptr %t90, align 4
  %t92 = getelementptr inbounds [34 x i8], ptr @.str.453, i64 0, i64 0
  %t93 = load ptr, ptr %pname.addr.74, align 8
  %t94 = call ptr @fmt-s(ptr %t92, ptr %t93)
  call void @die-at(i32 %t91, ptr %t94)
  br label %cond.end7
cond.end7:
  %t95 = load ptr, ptr %param-types.addr.52, align 8
  %t96 = load i32, ptr %i.addr.66, align 4
  %t97 = sext i32 %t96 to i64
  %t98 = load ptr, ptr %ptype-name.addr.75, align 8
  %t99 = load ptr, ptr %p.addr.70, align 8
  %t100 = getelementptr inbounds %Node, ptr %t99, i32 0, i32 1
  %t101 = load i32, ptr %t100, align 4
  %t102 = call ptr @parse-type-name(ptr %t98, i32 %t101)
  %t103 = getelementptr inbounds ptr, ptr %t95, i64 %t97
  store ptr %t102, ptr %t103, align 8
  %t104 = load ptr, ptr %param-names.addr.53, align 8
  %t105 = load i32, ptr %i.addr.66, align 4
  %t106 = sext i32 %t105 to i64
  %t107 = load ptr, ptr %pname.addr.74, align 8
  %t108 = getelementptr inbounds ptr, ptr %t104, i64 %t106
  store ptr %t107, ptr %t108, align 8
  %t109 = load i32, ptr %i.addr.66, align 4
  %t110 = add nsw i32 %t109, 1
  store i32 %t110, ptr %i.addr.66, align 4
  br label %while.cond5
while.end5:
  %t112 = call ptr @make-type(i32 7)
  store ptr %t112, ptr %ft.addr.111, align 8
  %t113 = load ptr, ptr %ft.addr.111, align 8
  %t114 = load ptr, ptr %ret.addr.43, align 8
  %t115 = getelementptr inbounds %Type, ptr %t113, i32 0, i32 1
  store ptr %t114, ptr %t115, align 8
  %t116 = load ptr, ptr %ft.addr.111, align 8
  %t117 = load i32, ptr %nparams.addr.49, align 4
  %t118 = getelementptr inbounds %Type, ptr %t116, i32 0, i32 3
  store i32 %t117, ptr %t118, align 4
  %t119 = load ptr, ptr %ft.addr.111, align 8
  %t120 = load ptr, ptr %param-types.addr.52, align 8
  %t121 = getelementptr inbounds %Type, ptr %t119, i32 0, i32 2
  store ptr %t120, ptr %t121, align 8
  %t122 = load ptr, ptr %ft.addr.111, align 8
  %t123 = getelementptr inbounds %Type, ptr %t122, i32 0, i32 4
  store i32 0, ptr %t123, align 4
  %t124 = load ptr, ptr @g-globals, align 8
  %t125 = load ptr, ptr %fname.addr.30, align 8
  %t126 = load ptr, ptr %ft.addr.111, align 8
  %t127 = getelementptr inbounds [4 x i8], ptr @.str.454, i64 0, i64 0
  %t128 = load ptr, ptr %fname.addr.30, align 8
  %t129 = call ptr @fmt-s(ptr %t127, ptr %t128)
  %t130 = call ptr @scope-define(ptr %t124, ptr %t125, ptr %t126, ptr %t129, i32 0)
  call void @reset-function-state()
  %t132 = load ptr, ptr @g-globals, align 8
  %t133 = call ptr @scope-new(ptr %t132)
  store ptr %t133, ptr %fn-scope.addr.131, align 8
  store i32 0, ptr %i.addr.134, align 4
  br label %while.cond8
while.cond8:
  %t135 = load i32, ptr %i.addr.134, align 4
  %t136 = load i32, ptr %nparams.addr.49, align 4
  %t137 = icmp slt i32 %t135, %t136
  br i1 %t137, label %while.body8, label %while.end8
while.body8:
  %t139 = load ptr, ptr %param-names.addr.53, align 8
  %t140 = load i32, ptr %i.addr.134, align 4
  %t141 = sext i32 %t140 to i64
  %t142 = getelementptr inbounds ptr, ptr %t139, i64 %t141
  %t143 = load ptr, ptr %t142, align 8
  store ptr %t143, ptr %pname.addr.138, align 8
  %t145 = load ptr, ptr %param-types.addr.52, align 8
  %t146 = load i32, ptr %i.addr.134, align 4
  %t147 = sext i32 %t146 to i64
  %t148 = getelementptr inbounds ptr, ptr %t145, i64 %t147
  %t149 = load ptr, ptr %t148, align 8
  store ptr %t149, ptr %ptype.addr.144, align 8
  %t151 = getelementptr inbounds [10 x i8], ptr @.str.455, i64 0, i64 0
  %t152 = load ptr, ptr %pname.addr.138, align 8
  %t153 = call ptr @fmt-s(ptr %t151, ptr %t152)
  store ptr %t153, ptr %slot.addr.150, align 8
  %t155 = getelementptr inbounds [9 x i8], ptr @.str.456, i64 0, i64 0
  %t156 = load ptr, ptr %pname.addr.138, align 8
  %t157 = call ptr @fmt-s(ptr %t155, ptr %t156)
  store ptr %t157, ptr %arg.addr.154, align 8
  %t159 = load ptr, ptr %ptype.addr.144, align 8
  %t160 = call i32 @type-size(ptr %t159)
  store i32 %t160, ptr %palign.addr.158, align 4
  %t161 = load ptr, ptr @g-entry-stream, align 8
  %t162 = getelementptr inbounds [28 x i8], ptr @.str.457, i64 0, i64 0
  %t163 = load ptr, ptr %slot.addr.150, align 8
  %t164 = load ptr, ptr %ptype.addr.144, align 8
  %t165 = call ptr @type-to-ir(ptr %t164)
  %t166 = load i32, ptr %palign.addr.158, align 4
  %t167 = call i32 (ptr, ptr, ...) @fprintf(ptr %t161, ptr %t162, ptr %t163, ptr %t165, i32 %t166)
  %t168 = load ptr, ptr @g-entry-stream, align 8
  %t169 = getelementptr inbounds [33 x i8], ptr @.str.458, i64 0, i64 0
  %t170 = load ptr, ptr %ptype.addr.144, align 8
  %t171 = call ptr @type-to-ir(ptr %t170)
  %t172 = load ptr, ptr %arg.addr.154, align 8
  %t173 = load ptr, ptr %slot.addr.150, align 8
  %t174 = load i32, ptr %palign.addr.158, align 4
  %t175 = call i32 (ptr, ptr, ...) @fprintf(ptr %t168, ptr %t169, ptr %t171, ptr %t172, ptr %t173, i32 %t174)
  %t176 = load ptr, ptr %fn-scope.addr.131, align 8
  %t177 = load ptr, ptr %pname.addr.138, align 8
  %t178 = load ptr, ptr %ptype.addr.144, align 8
  %t179 = load ptr, ptr %slot.addr.150, align 8
  %t180 = call ptr @scope-define(ptr %t176, ptr %t177, ptr %t178, ptr %t179, i32 1)
  %t181 = load i32, ptr %i.addr.134, align 4
  %t182 = add nsw i32 %t181, 1
  store i32 %t182, ptr %i.addr.134, align 4
  br label %while.cond8
while.end8:
  store i32 3, ptr %i.addr.134, align 4
  br label %while.cond9
while.cond9:
  %t183 = load i32, ptr %i.addr.134, align 4
  %t184 = load ptr, ptr %cc.addr.0, align 8
  %t185 = call i32 @node-len(ptr %t184)
  %t186 = icmp slt i32 %t183, %t185
  br i1 %t186, label %while.body9, label %while.end9
while.body9:
  %t187 = load ptr, ptr %cc.addr.0, align 8
  %t188 = load i32, ptr %i.addr.134, align 4
  %t189 = call ptr @node-at(ptr %t187, i32 %t188)
  %t190 = load ptr, ptr %fn-scope.addr.131, align 8
  %t191 = call ptr @emit-node(ptr %t189, ptr %t190)
  %t192 = load i32, ptr %i.addr.134, align 4
  %t193 = add nsw i32 %t192, 1
  store i32 %t193, ptr %i.addr.134, align 4
  br label %while.cond9
while.end9:
  %t194 = load i32, ptr @g-block-term, align 4
  %t195 = icmp eq i32 %t194, 0
  br i1 %t195, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t196 = load ptr, ptr %ret.addr.43, align 8
  %t197 = getelementptr inbounds %Type, ptr %t196, i32 0, i32 0
  %t198 = load i32, ptr %t197, align 4
  %t199 = icmp eq i32 %t198, 0
  br i1 %t199, label %cond.then11.0, label %cond.test11.1
cond.then11.0:
  %t200 = load ptr, ptr @g-body-stream, align 8
  %t201 = getelementptr inbounds [12 x i8], ptr @.str.459, i64 0, i64 0
  %t202 = call i32 (ptr, ptr, ...) @fprintf(ptr %t200, ptr %t201)
  br label %cond.end11
cond.test11.1:
  br i1 1, label %cond.then11.1, label %cond.end11
cond.then11.1:
  %t204 = getelementptr inbounds [2 x i8], ptr @.str.460, i64 0, i64 0
  store ptr %t204, ptr %zero.addr.203, align 8
  %t205 = load ptr, ptr %ret.addr.43, align 8
  %t206 = getelementptr inbounds %Type, ptr %t205, i32 0, i32 0
  %t207 = load i32, ptr %t206, align 4
  %t208 = icmp eq i32 %t207, 6
  br i1 %t208, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t209 = getelementptr inbounds [5 x i8], ptr @.str.461, i64 0, i64 0
  store ptr %t209, ptr %zero.addr.203, align 8
  br label %cond.end12
cond.end12:
  %t210 = load ptr, ptr @g-body-stream, align 8
  %t211 = getelementptr inbounds [13 x i8], ptr @.str.462, i64 0, i64 0
  %t212 = load ptr, ptr %ret.addr.43, align 8
  %t213 = call ptr @type-to-ir(ptr %t212)
  %t214 = load ptr, ptr %zero.addr.203, align 8
  %t215 = call i32 (ptr, ptr, ...) @fprintf(ptr %t210, ptr %t211, ptr %t213, ptr %t214)
  br label %cond.end11
cond.end11:
  br label %cond.end10
cond.end10:
  %t216 = load ptr, ptr @g-entry-stream, align 8
  %t217 = call i32 @fclose(ptr %t216)
  %t218 = load ptr, ptr @g-body-stream, align 8
  %t219 = call i32 @fclose(ptr %t218)
  %t220 = load ptr, ptr @g-out, align 8
  %t221 = getelementptr inbounds [15 x i8], ptr @.str.463, i64 0, i64 0
  %t222 = load ptr, ptr %ret.addr.43, align 8
  %t223 = call ptr @type-to-ir(ptr %t222)
  %t224 = load ptr, ptr %fname.addr.30, align 8
  %t225 = call i32 (ptr, ptr, ...) @fprintf(ptr %t220, ptr %t221, ptr %t223, ptr %t224)
  store i32 0, ptr %i.addr.134, align 4
  br label %while.cond13
while.cond13:
  %t226 = load i32, ptr %i.addr.134, align 4
  %t227 = load i32, ptr %nparams.addr.49, align 4
  %t228 = icmp slt i32 %t226, %t227
  br i1 %t228, label %while.body13, label %while.end13
while.body13:
  %t229 = load i32, ptr %i.addr.134, align 4
  %t230 = icmp ne i32 %t229, 0
  br i1 %t230, label %cond.then14.0, label %cond.end14
cond.then14.0:
  %t231 = load ptr, ptr @g-out, align 8
  %t232 = getelementptr inbounds [3 x i8], ptr @.str.464, i64 0, i64 0
  %t233 = call i32 (ptr, ptr, ...) @fprintf(ptr %t231, ptr %t232)
  br label %cond.end14
cond.end14:
  %t234 = load ptr, ptr @g-out, align 8
  %t235 = getelementptr inbounds [12 x i8], ptr @.str.465, i64 0, i64 0
  %t236 = load ptr, ptr %param-types.addr.52, align 8
  %t237 = load i32, ptr %i.addr.134, align 4
  %t238 = sext i32 %t237 to i64
  %t239 = getelementptr inbounds ptr, ptr %t236, i64 %t238
  %t240 = load ptr, ptr %t239, align 8
  %t241 = call ptr @type-to-ir(ptr %t240)
  %t242 = load ptr, ptr %param-names.addr.53, align 8
  %t243 = load i32, ptr %i.addr.134, align 4
  %t244 = sext i32 %t243 to i64
  %t245 = getelementptr inbounds ptr, ptr %t242, i64 %t244
  %t246 = load ptr, ptr %t245, align 8
  %t247 = call i32 (ptr, ptr, ...) @fprintf(ptr %t234, ptr %t235, ptr %t241, ptr %t246)
  %t248 = load i32, ptr %i.addr.134, align 4
  %t249 = add nsw i32 %t248, 1
  store i32 %t249, ptr %i.addr.134, align 4
  br label %while.cond13
while.end13:
  %t250 = load ptr, ptr @g-out, align 8
  %t251 = getelementptr inbounds [5 x i8], ptr @.str.466, i64 0, i64 0
  %t252 = call i32 (ptr, ptr, ...) @fprintf(ptr %t250, ptr %t251)
  %t253 = load ptr, ptr @g-out, align 8
  %t254 = getelementptr inbounds [8 x i8], ptr @.str.467, i64 0, i64 0
  %t255 = call i32 (ptr, ptr, ...) @fprintf(ptr %t253, ptr %t254)
  %t256 = load ptr, ptr @g-entry-bufp, align 8
  %t257 = icmp ne ptr %t256, null
  store i1 %t257, ptr %and.val16, align 1
  br i1 %t257, label %and.rhs16, label %and.end16
and.rhs16:
  %t258 = load ptr, ptr @g-entry-bufp, align 8
  %t259 = sext i32 0 to i64
  %t260 = call i32 @char-at(ptr %t258, i64 %t259)
  %t261 = icmp ne i32 %t260, 0
  store i1 %t261, ptr %and.val16, align 1
  br label %and.end16
and.end16:
  %t262 = load i1, ptr %and.val16, align 1
  br i1 %t262, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t263 = load ptr, ptr @g-entry-bufp, align 8
  %t264 = load ptr, ptr @g-out, align 8
  %t265 = call i32 @fputs(ptr %t263, ptr %t264)
  br label %cond.end15
cond.end15:
  %t266 = load ptr, ptr @g-body-bufp, align 8
  %t267 = icmp ne ptr %t266, null
  store i1 %t267, ptr %and.val18, align 1
  br i1 %t267, label %and.rhs18, label %and.end18
and.rhs18:
  %t268 = load ptr, ptr @g-body-bufp, align 8
  %t269 = sext i32 0 to i64
  %t270 = call i32 @char-at(ptr %t268, i64 %t269)
  %t271 = icmp ne i32 %t270, 0
  store i1 %t271, ptr %and.val18, align 1
  br label %and.end18
and.end18:
  %t272 = load i1, ptr %and.val18, align 1
  br i1 %t272, label %cond.then17.0, label %cond.end17
cond.then17.0:
  %t273 = load ptr, ptr @g-body-bufp, align 8
  %t274 = load ptr, ptr @g-out, align 8
  %t275 = call i32 @fputs(ptr %t273, ptr %t274)
  br label %cond.end17
cond.end17:
  %t276 = load ptr, ptr @g-out, align 8
  %t277 = getelementptr inbounds [4 x i8], ptr @.str.468, i64 0, i64 0
  %t278 = call i32 (ptr, ptr, ...) @fprintf(ptr %t276, ptr %t277)
  %t279 = load ptr, ptr @g-entry-bufp, align 8
  call void @free(ptr %t279)
  %t280 = load ptr, ptr @g-body-bufp, align 8
  call void @free(ptr %t280)
  store ptr null, ptr @g-entry-bufp, align 8
  store ptr null, ptr @g-body-bufp, align 8
  ret void
}

define void @jit-ensure-init(i32 %line.arg) {
entry:
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %jit-ref.addr.2 = alloca ptr, align 8
  %err.addr.3 = alloca ptr, align 8
  %prefix.addr.17 = alloca i8, align 1
  %gen.addr.20 = alloca ptr, align 8
  %err.addr.21 = alloca ptr, align 8
  %t0 = load ptr, ptr @g-jit, align 8
  %t1 = icmp ne ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret void
cond.end0:
  call void @LLVMInitializeX86TargetInfo()
  call void @LLVMInitializeX86Target()
  call void @LLVMInitializeX86TargetMC()
  call void @LLVMInitializeX86AsmPrinter()
  store ptr null, ptr %jit-ref.addr.2, align 8
  %t4 = call ptr @LLVMOrcCreateLLJIT(ptr %jit-ref.addr.2, ptr null)
  store ptr %t4, ptr %err.addr.3, align 8
  %t5 = load ptr, ptr %err.addr.3, align 8
  %t6 = icmp ne ptr %t5, null
  br i1 %t6, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t7 = load ptr, ptr @stderr, align 8
  %t8 = getelementptr inbounds [44 x i8], ptr @.str.469, i64 0, i64 0
  %t9 = load ptr, ptr @g-source-path, align 8
  %t10 = load i32, ptr %line.addr, align 4
  %t11 = load ptr, ptr %err.addr.3, align 8
  %t12 = call ptr @LLVMGetErrorMessage(ptr %t11)
  %t13 = call i32 (ptr, ptr, ...) @fprintf(ptr %t7, ptr %t8, ptr %t9, i32 %t10, ptr %t12)
  call void @exit(i32 1)
  br label %cond.end1
cond.end1:
  %t14 = load ptr, ptr %jit-ref.addr.2, align 8
  store ptr %t14, ptr @g-jit, align 8
  %t15 = load ptr, ptr @g-jit, align 8
  %t16 = call ptr @LLVMOrcLLJITGetMainJITDylib(ptr %t15)
  store ptr %t16, ptr @g-jit-dylib, align 8
  %t18 = load ptr, ptr @g-jit, align 8
  %t19 = call i8 @LLVMOrcLLJITGetGlobalPrefix(ptr %t18)
  store i8 %t19, ptr %prefix.addr.17, align 1
  store ptr null, ptr %gen.addr.20, align 8
  %t22 = load i8, ptr %prefix.addr.17, align 1
  %t23 = call ptr @LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess(ptr %gen.addr.20, i8 %t22, ptr null, ptr null)
  store ptr %t23, ptr %err.addr.21, align 8
  %t24 = load ptr, ptr %err.addr.21, align 8
  %t25 = icmp ne ptr %t24, null
  br i1 %t25, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t26 = load ptr, ptr @stderr, align 8
  %t27 = getelementptr inbounds [47 x i8], ptr @.str.470, i64 0, i64 0
  %t28 = load ptr, ptr @g-source-path, align 8
  %t29 = load i32, ptr %line.addr, align 4
  %t30 = load ptr, ptr %err.addr.21, align 8
  %t31 = call ptr @LLVMGetErrorMessage(ptr %t30)
  %t32 = call i32 (ptr, ptr, ...) @fprintf(ptr %t26, ptr %t27, ptr %t28, i32 %t29, ptr %t31)
  call void @exit(i32 1)
  br label %cond.end2
cond.end2:
  %t33 = load ptr, ptr @g-jit-dylib, align 8
  %t34 = load ptr, ptr %gen.addr.20, align 8
  call void @LLVMOrcJITDylibAddGenerator(ptr %t33, ptr %t34)
  ret void
}

define void @jit-add-module(ptr %ir.arg, i32 %line.arg) {
entry:
  %ir.addr = alloca ptr, align 8
  store ptr %ir.arg, ptr %ir.addr, align 8
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %ctx.addr.1 = alloca ptr, align 8
  %ir-len.addr.3 = alloca i64, align 8
  %mb.addr.6 = alloca ptr, align 8
  %mod.addr.11 = alloca ptr, align 8
  %errmsg.addr.12 = alloca ptr, align 8
  %parse-err.addr.13 = alloca i32, align 4
  %tsctx.addr.25 = alloca ptr, align 8
  %tsmod.addr.27 = alloca ptr, align 8
  %err.addr.32 = alloca ptr, align 8
  %t0 = load i32, ptr %line.addr, align 4
  call void @jit-ensure-init(i32 %t0)
  %t2 = call ptr @LLVMContextCreate()
  store ptr %t2, ptr %ctx.addr.1, align 8
  %t4 = load ptr, ptr %ir.addr, align 8
  %t5 = call i64 @strlen(ptr %t4)
  store i64 %t5, ptr %ir-len.addr.3, align 8
  %t7 = load ptr, ptr %ir.addr, align 8
  %t8 = load i64, ptr %ir-len.addr.3, align 8
  %t9 = getelementptr inbounds [15 x i8], ptr @.str.471, i64 0, i64 0
  %t10 = call ptr @LLVMCreateMemoryBufferWithMemoryRangeCopy(ptr %t7, i64 %t8, ptr %t9)
  store ptr %t10, ptr %mb.addr.6, align 8
  store ptr null, ptr %mod.addr.11, align 8
  store ptr null, ptr %errmsg.addr.12, align 8
  %t14 = load ptr, ptr %ctx.addr.1, align 8
  %t15 = load ptr, ptr %mb.addr.6, align 8
  %t16 = call i32 @LLVMParseIRInContext(ptr %t14, ptr %t15, ptr %mod.addr.11, ptr %errmsg.addr.12)
  store i32 %t16, ptr %parse-err.addr.13, align 4
  %t17 = load i32, ptr %parse-err.addr.13, align 4
  %t18 = icmp ne i32 %t17, 0
  br i1 %t18, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t19 = load ptr, ptr @stderr, align 8
  %t20 = getelementptr inbounds [41 x i8], ptr @.str.472, i64 0, i64 0
  %t21 = load ptr, ptr @g-source-path, align 8
  %t22 = load i32, ptr %line.addr, align 4
  %t23 = load ptr, ptr %errmsg.addr.12, align 8
  %t24 = call i32 (ptr, ptr, ...) @fprintf(ptr %t19, ptr %t20, ptr %t21, i32 %t22, ptr %t23)
  call void @exit(i32 1)
  br label %cond.end0
cond.end0:
  %t26 = call ptr @LLVMOrcCreateNewThreadSafeContext()
  store ptr %t26, ptr %tsctx.addr.25, align 8
  %t28 = load ptr, ptr %mod.addr.11, align 8
  %t29 = load ptr, ptr %tsctx.addr.25, align 8
  %t30 = call ptr @LLVMOrcCreateNewThreadSafeModule(ptr %t28, ptr %t29)
  store ptr %t30, ptr %tsmod.addr.27, align 8
  %t31 = load ptr, ptr %tsctx.addr.25, align 8
  call void @LLVMOrcDisposeThreadSafeContext(ptr %t31)
  %t33 = load ptr, ptr @g-jit, align 8
  %t34 = load ptr, ptr @g-jit-dylib, align 8
  %t35 = load ptr, ptr %tsmod.addr.27, align 8
  %t36 = call ptr @LLVMOrcLLJITAddLLVMIRModule(ptr %t33, ptr %t34, ptr %t35)
  store ptr %t36, ptr %err.addr.32, align 8
  %t37 = load ptr, ptr %err.addr.32, align 8
  %t38 = icmp ne ptr %t37, null
  br i1 %t38, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t39 = load ptr, ptr @stderr, align 8
  %t40 = getelementptr inbounds [41 x i8], ptr @.str.473, i64 0, i64 0
  %t41 = load ptr, ptr @g-source-path, align 8
  %t42 = load i32, ptr %line.addr, align 4
  %t43 = load ptr, ptr %err.addr.32, align 8
  %t44 = call ptr @LLVMGetErrorMessage(ptr %t43)
  %t45 = call i32 (ptr, ptr, ...) @fprintf(ptr %t39, ptr %t40, ptr %t41, i32 %t42, ptr %t44)
  call void @exit(i32 1)
  br label %cond.end1
cond.end1:
  ret void
}

define void @jit-call-ct-main-sym(i32 %line.arg, ptr %sym.arg) {
entry:
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %sym.addr = alloca ptr, align 8
  store ptr %sym.arg, ptr %sym.addr, align 8
  %addr.addr.0 = alloca i64, align 8
  %err.addr.2 = alloca ptr, align 8
  %saved-fd.addr.14 = alloca i32, align 4
  %t1 = sext i32 0 to i64
  store i64 %t1, ptr %addr.addr.0, align 8
  %t3 = load ptr, ptr @g-jit, align 8
  %t4 = load ptr, ptr %sym.addr, align 8
  %t5 = call ptr @LLVMOrcLLJITLookup(ptr %t3, ptr %addr.addr.0, ptr %t4)
  store ptr %t5, ptr %err.addr.2, align 8
  %t6 = load ptr, ptr %err.addr.2, align 8
  %t7 = icmp ne ptr %t6, null
  br i1 %t7, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t8 = load ptr, ptr %err.addr.2, align 8
  call void @LLVMConsumeError(ptr %t8)
  ret void
cond.end0:
  %t9 = load i64, ptr %addr.addr.0, align 8
  %t10 = sext i32 0 to i64
  %t11 = icmp eq i64 %t9, %t10
  br i1 %t11, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret void
cond.end1:
  %t12 = load ptr, ptr @stdout, align 8
  %t13 = call i32 @fflush(ptr %t12)
  %t15 = call i32 @dup(i32 1)
  store i32 %t15, ptr %saved-fd.addr.14, align 4
  %t16 = call i32 @dup2(i32 2, i32 1)
  %t17 = load i64, ptr %addr.addr.0, align 8
  %t18 = inttoptr i64 %t17 to ptr
  call void %t18()
  %t19 = load ptr, ptr @stdout, align 8
  %t20 = call i32 @fflush(ptr %t19)
  %t21 = load i32, ptr %saved-fd.addr.14, align 4
  %t22 = call i32 @dup2(i32 %t21, i32 1)
  %t23 = load i32, ptr %saved-fd.addr.14, align 4
  %t24 = call i32 @close(i32 %t23)
  ret void
}

define void @emit-compile-time(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %nforms.addr.0 = alloca i32, align 4
  %ff.addr.3 = alloca ptr, align 8
  %ct-type-bufp.addr.15 = alloca ptr, align 8
  %ct-type-sizep.addr.16 = alloca i64, align 8
  %ct-decl-bufp.addr.18 = alloca ptr, align 8
  %ct-decl-sizep.addr.19 = alloca i64, align 8
  %ct-def-bufp.addr.21 = alloca ptr, align 8
  %ct-def-sizep.addr.22 = alloca i64, align 8
  %ct-type.addr.24 = alloca ptr, align 8
  %ct-decl.addr.26 = alloca ptr, align 8
  %ct-def.addr.28 = alloca ptr, align 8
  %saved-g-out.addr.30 = alloca ptr, align 8
  %saved-decl-out.addr.32 = alloca ptr, align 8
  %saved-qq-used.addr.34 = alloca i32, align 4
  %bi.addr.37 = alloca i32, align 4
  %bf.addr.41 = alloca ptr, align 8
  %and.val3 = alloca i1, align 1
  %and.val4 = alloca i1, align 1
  %and.val5 = alloca i1, align 1
  %and.val6 = alloca i1, align 1
  %name-node.addr.70 = alloca ptr, align 8
  %params-node.addr.73 = alloca ptr, align 8
  %and.val8 = alloca i1, align 1
  %fname.addr.84 = alloca ptr, align 8
  %ret-name.addr.85 = alloca ptr, align 8
  %ret.addr.91 = alloca ptr, align 8
  %nparams.addr.97 = alloca i32, align 4
  %ptypes.addr.100 = alloca ptr, align 8
  %j.addr.108 = alloca i32, align 4
  %p.addr.112 = alloca ptr, align 8
  %pn.addr.120 = alloca ptr, align 8
  %pt-name.addr.121 = alloca ptr, align 8
  %ft.addr.143 = alloca ptr, align 8
  %expr-forms.addr.163 = alloca ptr, align 8
  %nexpr.addr.168 = alloca i32, align 4
  %bi.addr.169 = alloca i32, align 4
  %bf.addr.173 = alloca ptr, align 8
  %is-tl.addr.177 = alloca i32, align 4
  %and.val16 = alloca i1, align 1
  %and.val17 = alloca i1, align 1
  %and.val18 = alloca i1, align 1
  %bh.addr.195 = alloca ptr, align 8
  %and.val27 = alloca i1, align 1
  %ct-sym.addr.254 = alloca ptr, align 8
  %fn-scope.addr.262 = alloca ptr, align 8
  %ei.addr.265 = alloca i32, align 4
  %and.val31 = alloca i1, align 1
  %and.val33 = alloca i1, align 1
  %ct-qq.addr.319 = alloca i32, align 4
  %ir-bufp.addr.410 = alloca ptr, align 8
  %ir-sizep.addr.411 = alloca i64, align 8
  %irs.addr.413 = alloca ptr, align 8
  %and.val36 = alloca i1, align 1
  %and.val38 = alloca i1, align 1
  %and.val40 = alloca i1, align 1
  %and.val42 = alloca i1, align 1
  %and.val44 = alloca i1, align 1
  %t1 = load ptr, ptr %form.addr, align 8
  %t2 = call i32 @node-len(ptr %t1)
  store i32 %t2, ptr %nforms.addr.0, align 4
  %t4 = load ptr, ptr %form.addr, align 8
  store ptr %t4, ptr %ff.addr.3, align 8
  %t5 = load i32, ptr %nforms.addr.0, align 4
  %t6 = icmp slt i32 %t5, 2
  br i1 %t6, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t7 = load ptr, ptr %ff.addr.3, align 8
  %t8 = getelementptr inbounds %Node, ptr %t7, i32 0, i32 1
  %t9 = load i32, ptr %t8, align 4
  %t10 = getelementptr inbounds [46 x i8], ptr @.str.474, i64 0, i64 0
  call void @die-at(i32 %t9, ptr %t10)
  br label %cond.end0
cond.end0:
  %t11 = load ptr, ptr @g-type-stream, align 8
  %t12 = call i32 @fflush(ptr %t11)
  %t13 = load ptr, ptr @g-decl-stream, align 8
  %t14 = call i32 @fflush(ptr %t13)
  store ptr null, ptr %ct-type-bufp.addr.15, align 8
  %t17 = sext i32 0 to i64
  store i64 %t17, ptr %ct-type-sizep.addr.16, align 8
  store ptr null, ptr %ct-decl-bufp.addr.18, align 8
  %t20 = sext i32 0 to i64
  store i64 %t20, ptr %ct-decl-sizep.addr.19, align 8
  store ptr null, ptr %ct-def-bufp.addr.21, align 8
  %t23 = sext i32 0 to i64
  store i64 %t23, ptr %ct-def-sizep.addr.22, align 8
  %t25 = call ptr @open_memstream(ptr %ct-type-bufp.addr.15, ptr %ct-type-sizep.addr.16)
  store ptr %t25, ptr %ct-type.addr.24, align 8
  %t27 = call ptr @open_memstream(ptr %ct-decl-bufp.addr.18, ptr %ct-decl-sizep.addr.19)
  store ptr %t27, ptr %ct-decl.addr.26, align 8
  %t29 = call ptr @open_memstream(ptr %ct-def-bufp.addr.21, ptr %ct-def-sizep.addr.22)
  store ptr %t29, ptr %ct-def.addr.28, align 8
  %t31 = load ptr, ptr @g-out, align 8
  store ptr %t31, ptr %saved-g-out.addr.30, align 8
  %t33 = load ptr, ptr @g-decl-out, align 8
  store ptr %t33, ptr %saved-decl-out.addr.32, align 8
  %t35 = load i32, ptr @g-qq-used, align 4
  store i32 %t35, ptr %saved-qq-used.addr.34, align 4
  store i32 0, ptr @g-qq-used, align 4
  %t36 = load ptr, ptr %ct-decl.addr.26, align 8
  store ptr %t36, ptr @g-decl-out, align 8
  store i32 1, ptr %bi.addr.37, align 4
  br label %while.cond1
while.cond1:
  %t38 = load i32, ptr %bi.addr.37, align 4
  %t39 = load i32, ptr %nforms.addr.0, align 4
  %t40 = icmp slt i32 %t38, %t39
  br i1 %t40, label %while.body1, label %while.end1
while.body1:
  %t42 = load ptr, ptr %ff.addr.3, align 8
  %t43 = load i32, ptr %bi.addr.37, align 4
  %t44 = call ptr @node-at(ptr %t42, i32 %t43)
  store ptr %t44, ptr %bf.addr.41, align 8
  %t45 = load ptr, ptr %bf.addr.41, align 8
  %t46 = icmp ne ptr %t45, null
  store i1 %t46, ptr %and.val3, align 1
  br i1 %t46, label %and.rhs3, label %and.end3
and.rhs3:
  %t47 = load ptr, ptr %bf.addr.41, align 8
  %t48 = getelementptr inbounds %Node, ptr %t47, i32 0, i32 0
  %t49 = load i32, ptr %t48, align 4
  %t50 = icmp eq i32 %t49, 3
  store i1 %t50, ptr %and.val4, align 1
  br i1 %t50, label %and.rhs4, label %and.end4
and.rhs4:
  %t51 = load ptr, ptr %bf.addr.41, align 8
  %t52 = call i32 @node-len(ptr %t51)
  %t53 = icmp sge i32 %t52, 4
  store i1 %t53, ptr %and.val5, align 1
  br i1 %t53, label %and.rhs5, label %and.end5
and.rhs5:
  %t54 = load ptr, ptr %bf.addr.41, align 8
  %t55 = call ptr @node-at(ptr %t54, i32 0)
  %t56 = getelementptr inbounds %Node, ptr %t55, i32 0, i32 0
  %t57 = load i32, ptr %t56, align 4
  %t58 = icmp eq i32 %t57, 2
  store i1 %t58, ptr %and.val6, align 1
  br i1 %t58, label %and.rhs6, label %and.end6
and.rhs6:
  %t59 = load ptr, ptr %bf.addr.41, align 8
  %t60 = call ptr @node-at(ptr %t59, i32 0)
  %t61 = getelementptr inbounds %Node, ptr %t60, i32 0, i32 3
  %t62 = load ptr, ptr %t61, align 8
  %t63 = getelementptr inbounds [5 x i8], ptr @.str.475, i64 0, i64 0
  %t64 = call i32 @strcmp(ptr %t62, ptr %t63)
  %t65 = icmp eq i32 %t64, 0
  store i1 %t65, ptr %and.val6, align 1
  br label %and.end6
and.end6:
  %t66 = load i1, ptr %and.val6, align 1
  store i1 %t66, ptr %and.val5, align 1
  br label %and.end5
and.end5:
  %t67 = load i1, ptr %and.val5, align 1
  store i1 %t67, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t68 = load i1, ptr %and.val4, align 1
  store i1 %t68, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t69 = load i1, ptr %and.val3, align 1
  br i1 %t69, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t71 = load ptr, ptr %bf.addr.41, align 8
  %t72 = call ptr @node-at(ptr %t71, i32 1)
  store ptr %t72, ptr %name-node.addr.70, align 8
  %t74 = load ptr, ptr %bf.addr.41, align 8
  %t75 = call ptr @node-at(ptr %t74, i32 2)
  store ptr %t75, ptr %params-node.addr.73, align 8
  %t76 = load ptr, ptr %name-node.addr.70, align 8
  %t77 = getelementptr inbounds %Node, ptr %t76, i32 0, i32 0
  %t78 = load i32, ptr %t77, align 4
  %t79 = icmp eq i32 %t78, 2
  store i1 %t79, ptr %and.val8, align 1
  br i1 %t79, label %and.rhs8, label %and.end8
and.rhs8:
  %t80 = load ptr, ptr %params-node.addr.73, align 8
  %t81 = call i32 @node-is-list(ptr %t80)
  %t82 = icmp ne i32 %t81, 0
  store i1 %t82, ptr %and.val8, align 1
  br label %and.end8
and.end8:
  %t83 = load i1, ptr %and.val8, align 1
  br i1 %t83, label %cond.then7.0, label %cond.end7
cond.then7.0:
  store ptr null, ptr %fname.addr.84, align 8
  store ptr null, ptr %ret-name.addr.85, align 8
  %t86 = load ptr, ptr %name-node.addr.70, align 8
  %t87 = getelementptr inbounds %Node, ptr %t86, i32 0, i32 3
  %t88 = load ptr, ptr %t87, align 8
  call void @split-typed(ptr %t88, ptr %fname.addr.84, ptr %ret-name.addr.85)
  %t89 = load ptr, ptr %ret-name.addr.85, align 8
  %t90 = icmp ne ptr %t89, null
  br i1 %t90, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t92 = load ptr, ptr %ret-name.addr.85, align 8
  %t93 = load ptr, ptr %name-node.addr.70, align 8
  %t94 = getelementptr inbounds %Node, ptr %t93, i32 0, i32 1
  %t95 = load i32, ptr %t94, align 4
  %t96 = call ptr @parse-type-name(ptr %t92, i32 %t95)
  store ptr %t96, ptr %ret.addr.91, align 8
  %t98 = load ptr, ptr %params-node.addr.73, align 8
  %t99 = call i32 @node-len(ptr %t98)
  store i32 %t99, ptr %nparams.addr.97, align 4
  store ptr null, ptr %ptypes.addr.100, align 8
  %t101 = load i32, ptr %nparams.addr.97, align 4
  %t102 = icmp sgt i32 %t101, 0
  br i1 %t102, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t103 = load i32, ptr %nparams.addr.97, align 4
  %t104 = call i64 @i64(i32 %t103)
  %t105 = call i64 @i64(i32 8)
  %t106 = mul nsw i64 %t104, %t105
  %t107 = call ptr @arena-alloc(i64 %t106)
  store ptr %t107, ptr %ptypes.addr.100, align 8
  br label %cond.end10
cond.end10:
  store i32 0, ptr %j.addr.108, align 4
  br label %while.cond11
while.cond11:
  %t109 = load i32, ptr %j.addr.108, align 4
  %t110 = load i32, ptr %nparams.addr.97, align 4
  %t111 = icmp slt i32 %t109, %t110
  br i1 %t111, label %while.body11, label %while.end11
while.body11:
  %t113 = load ptr, ptr %params-node.addr.73, align 8
  %t114 = load i32, ptr %j.addr.108, align 4
  %t115 = call ptr @node-at(ptr %t113, i32 %t114)
  store ptr %t115, ptr %p.addr.112, align 8
  %t116 = load ptr, ptr %p.addr.112, align 8
  %t117 = getelementptr inbounds %Node, ptr %t116, i32 0, i32 0
  %t118 = load i32, ptr %t117, align 4
  %t119 = icmp eq i32 %t118, 2
  br i1 %t119, label %cond.then12.0, label %cond.end12
cond.then12.0:
  store ptr null, ptr %pn.addr.120, align 8
  store ptr null, ptr %pt-name.addr.121, align 8
  %t122 = load ptr, ptr %p.addr.112, align 8
  %t123 = getelementptr inbounds %Node, ptr %t122, i32 0, i32 3
  %t124 = load ptr, ptr %t123, align 8
  call void @split-typed(ptr %t124, ptr %pn.addr.120, ptr %pt-name.addr.121)
  %t125 = load ptr, ptr %pt-name.addr.121, align 8
  %t126 = icmp ne ptr %t125, null
  br i1 %t126, label %cond.then13.0, label %cond.test13.1
cond.then13.0:
  %t127 = load ptr, ptr %ptypes.addr.100, align 8
  %t128 = load i32, ptr %j.addr.108, align 4
  %t129 = sext i32 %t128 to i64
  %t130 = load ptr, ptr %pt-name.addr.121, align 8
  %t131 = load ptr, ptr %p.addr.112, align 8
  %t132 = getelementptr inbounds %Node, ptr %t131, i32 0, i32 1
  %t133 = load i32, ptr %t132, align 4
  %t134 = call ptr @parse-type-name(ptr %t130, i32 %t133)
  %t135 = getelementptr inbounds ptr, ptr %t127, i64 %t129
  store ptr %t134, ptr %t135, align 8
  br label %cond.end13
cond.test13.1:
  br i1 1, label %cond.then13.1, label %cond.end13
cond.then13.1:
  %t136 = load ptr, ptr %ptypes.addr.100, align 8
  %t137 = load i32, ptr %j.addr.108, align 4
  %t138 = sext i32 %t137 to i64
  %t139 = load ptr, ptr @ty-i32, align 8
  %t140 = getelementptr inbounds ptr, ptr %t136, i64 %t138
  store ptr %t139, ptr %t140, align 8
  br label %cond.end13
cond.end13:
  br label %cond.end12
cond.end12:
  %t141 = load i32, ptr %j.addr.108, align 4
  %t142 = add nsw i32 %t141, 1
  store i32 %t142, ptr %j.addr.108, align 4
  br label %while.cond11
while.end11:
  %t144 = call ptr @make-type(i32 7)
  store ptr %t144, ptr %ft.addr.143, align 8
  %t145 = load ptr, ptr %ft.addr.143, align 8
  %t146 = load ptr, ptr %ret.addr.91, align 8
  %t147 = getelementptr inbounds %Type, ptr %t145, i32 0, i32 1
  store ptr %t146, ptr %t147, align 8
  %t148 = load ptr, ptr %ft.addr.143, align 8
  %t149 = load i32, ptr %nparams.addr.97, align 4
  %t150 = getelementptr inbounds %Type, ptr %t148, i32 0, i32 3
  store i32 %t149, ptr %t150, align 4
  %t151 = load ptr, ptr %ft.addr.143, align 8
  %t152 = load ptr, ptr %ptypes.addr.100, align 8
  %t153 = getelementptr inbounds %Type, ptr %t151, i32 0, i32 2
  store ptr %t152, ptr %t153, align 8
  %t154 = load ptr, ptr @g-globals, align 8
  %t155 = load ptr, ptr %fname.addr.84, align 8
  %t156 = load ptr, ptr %ft.addr.143, align 8
  %t157 = getelementptr inbounds [4 x i8], ptr @.str.476, i64 0, i64 0
  %t158 = load ptr, ptr %fname.addr.84, align 8
  %t159 = call ptr @fmt-s(ptr %t157, ptr %t158)
  %t160 = call ptr @scope-define(ptr %t154, ptr %t155, ptr %t156, ptr %t159, i32 0)
  br label %cond.end9
cond.end9:
  br label %cond.end7
cond.end7:
  br label %cond.end2
cond.end2:
  %t161 = load i32, ptr %bi.addr.37, align 4
  %t162 = add nsw i32 %t161, 1
  store i32 %t162, ptr %bi.addr.37, align 4
  br label %while.cond1
while.end1:
  %t164 = sext i32 256 to i64
  %t165 = sext i32 8 to i64
  %t166 = mul nsw i64 %t164, %t165
  %t167 = call ptr @arena-alloc(i64 %t166)
  store ptr %t167, ptr %expr-forms.addr.163, align 8
  store i32 0, ptr %nexpr.addr.168, align 4
  store i32 1, ptr %bi.addr.169, align 4
  br label %while.cond14
while.cond14:
  %t170 = load i32, ptr %bi.addr.169, align 4
  %t171 = load i32, ptr %nforms.addr.0, align 4
  %t172 = icmp slt i32 %t170, %t171
  br i1 %t172, label %while.body14, label %while.end14
while.body14:
  %t174 = load ptr, ptr %ff.addr.3, align 8
  %t175 = load i32, ptr %bi.addr.169, align 4
  %t176 = call ptr @node-at(ptr %t174, i32 %t175)
  store ptr %t176, ptr %bf.addr.173, align 8
  store i32 0, ptr %is-tl.addr.177, align 4
  %t178 = load ptr, ptr %bf.addr.173, align 8
  %t179 = icmp ne ptr %t178, null
  store i1 %t179, ptr %and.val16, align 1
  br i1 %t179, label %and.rhs16, label %and.end16
and.rhs16:
  %t180 = load ptr, ptr %bf.addr.173, align 8
  %t181 = getelementptr inbounds %Node, ptr %t180, i32 0, i32 0
  %t182 = load i32, ptr %t181, align 4
  %t183 = icmp eq i32 %t182, 3
  store i1 %t183, ptr %and.val17, align 1
  br i1 %t183, label %and.rhs17, label %and.end17
and.rhs17:
  %t184 = load ptr, ptr %bf.addr.173, align 8
  %t185 = call i32 @node-len(ptr %t184)
  %t186 = icmp ne i32 %t185, 0
  store i1 %t186, ptr %and.val18, align 1
  br i1 %t186, label %and.rhs18, label %and.end18
and.rhs18:
  %t187 = load ptr, ptr %bf.addr.173, align 8
  %t188 = call ptr @node-at(ptr %t187, i32 0)
  %t189 = getelementptr inbounds %Node, ptr %t188, i32 0, i32 0
  %t190 = load i32, ptr %t189, align 4
  %t191 = icmp eq i32 %t190, 2
  store i1 %t191, ptr %and.val18, align 1
  br label %and.end18
and.end18:
  %t192 = load i1, ptr %and.val18, align 1
  store i1 %t192, ptr %and.val17, align 1
  br label %and.end17
and.end17:
  %t193 = load i1, ptr %and.val17, align 1
  store i1 %t193, ptr %and.val16, align 1
  br label %and.end16
and.end16:
  %t194 = load i1, ptr %and.val16, align 1
  br i1 %t194, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t196 = load ptr, ptr %bf.addr.173, align 8
  %t197 = call ptr @node-at(ptr %t196, i32 0)
  %t198 = getelementptr inbounds %Node, ptr %t197, i32 0, i32 3
  %t199 = load ptr, ptr %t198, align 8
  store ptr %t199, ptr %bh.addr.195, align 8
  %t200 = load ptr, ptr %bh.addr.195, align 8
  %t201 = getelementptr inbounds [10 x i8], ptr @.str.477, i64 0, i64 0
  %t202 = call i32 @strcmp(ptr %t200, ptr %t201)
  %t203 = icmp eq i32 %t202, 0
  br i1 %t203, label %cond.then19.0, label %cond.end19
cond.then19.0:
  store i32 1, ptr %is-tl.addr.177, align 4
  %t204 = load ptr, ptr %ct-type.addr.24, align 8
  store ptr %t204, ptr @g-out, align 8
  %t205 = load ptr, ptr %bf.addr.173, align 8
  call void @emit-defstruct(ptr %t205)
  br label %cond.end19
cond.end19:
  %t206 = load ptr, ptr %bh.addr.195, align 8
  %t207 = getelementptr inbounds [9 x i8], ptr @.str.478, i64 0, i64 0
  %t208 = call i32 @strcmp(ptr %t206, ptr %t207)
  %t209 = icmp eq i32 %t208, 0
  br i1 %t209, label %cond.then20.0, label %cond.end20
cond.then20.0:
  store i32 1, ptr %is-tl.addr.177, align 4
  %t210 = load ptr, ptr %bf.addr.173, align 8
  call void @emit-defconst(ptr %t210)
  br label %cond.end20
cond.end20:
  %t211 = load ptr, ptr %bh.addr.195, align 8
  %t212 = getelementptr inbounds [8 x i8], ptr @.str.479, i64 0, i64 0
  %t213 = call i32 @strcmp(ptr %t211, ptr %t212)
  %t214 = icmp eq i32 %t213, 0
  br i1 %t214, label %cond.then21.0, label %cond.end21
cond.then21.0:
  store i32 1, ptr %is-tl.addr.177, align 4
  %t215 = load ptr, ptr %bf.addr.173, align 8
  call void @emit-defenum(ptr %t215)
  br label %cond.end21
cond.end21:
  %t216 = load ptr, ptr %bh.addr.195, align 8
  %t217 = getelementptr inbounds [7 x i8], ptr @.str.480, i64 0, i64 0
  %t218 = call i32 @strcmp(ptr %t216, ptr %t217)
  %t219 = icmp eq i32 %t218, 0
  br i1 %t219, label %cond.then22.0, label %cond.end22
cond.then22.0:
  store i32 1, ptr %is-tl.addr.177, align 4
  %t220 = load ptr, ptr %ct-decl.addr.26, align 8
  store ptr %t220, ptr @g-out, align 8
  %t221 = load ptr, ptr %bf.addr.173, align 8
  call void @emit-defvar(ptr %t221)
  br label %cond.end22
cond.end22:
  %t222 = load ptr, ptr %bh.addr.195, align 8
  %t223 = getelementptr inbounds [8 x i8], ptr @.str.481, i64 0, i64 0
  %t224 = call i32 @strcmp(ptr %t222, ptr %t223)
  %t225 = icmp eq i32 %t224, 0
  br i1 %t225, label %cond.then23.0, label %cond.end23
cond.then23.0:
  store i32 1, ptr %is-tl.addr.177, align 4
  %t226 = load ptr, ptr %ct-decl.addr.26, align 8
  store ptr %t226, ptr @g-out, align 8
  %t227 = load ptr, ptr %bf.addr.173, align 8
  call void @emit-include(ptr %t227)
  br label %cond.end23
cond.end23:
  %t228 = load ptr, ptr %bh.addr.195, align 8
  %t229 = getelementptr inbounds [7 x i8], ptr @.str.482, i64 0, i64 0
  %t230 = call i32 @strcmp(ptr %t228, ptr %t229)
  %t231 = icmp eq i32 %t230, 0
  br i1 %t231, label %cond.then24.0, label %cond.end24
cond.then24.0:
  store i32 1, ptr %is-tl.addr.177, align 4
  %t232 = load ptr, ptr %ct-decl.addr.26, align 8
  store ptr %t232, ptr @g-out, align 8
  %t233 = load ptr, ptr %bf.addr.173, align 8
  call void @emit-extern(ptr %t233)
  br label %cond.end24
cond.end24:
  %t234 = load ptr, ptr %bh.addr.195, align 8
  %t235 = getelementptr inbounds [5 x i8], ptr @.str.483, i64 0, i64 0
  %t236 = call i32 @strcmp(ptr %t234, ptr %t235)
  %t237 = icmp eq i32 %t236, 0
  br i1 %t237, label %cond.then25.0, label %cond.end25
cond.then25.0:
  store i32 1, ptr %is-tl.addr.177, align 4
  %t238 = load ptr, ptr %ct-def.addr.28, align 8
  store ptr %t238, ptr @g-out, align 8
  %t239 = load ptr, ptr %bf.addr.173, align 8
  call void @emit-defn(ptr %t239)
  br label %cond.end25
cond.end25:
  br label %cond.end15
cond.end15:
  %t240 = load i32, ptr %is-tl.addr.177, align 4
  %t241 = icmp eq i32 %t240, 0
  store i1 %t241, ptr %and.val27, align 1
  br i1 %t241, label %and.rhs27, label %and.end27
and.rhs27:
  %t242 = load i32, ptr %nexpr.addr.168, align 4
  %t243 = icmp slt i32 %t242, 256
  store i1 %t243, ptr %and.val27, align 1
  br label %and.end27
and.end27:
  %t244 = load i1, ptr %and.val27, align 1
  br i1 %t244, label %cond.then26.0, label %cond.end26
cond.then26.0:
  %t245 = load ptr, ptr %expr-forms.addr.163, align 8
  %t246 = load i32, ptr %nexpr.addr.168, align 4
  %t247 = sext i32 %t246 to i64
  %t248 = load ptr, ptr %bf.addr.173, align 8
  %t249 = getelementptr inbounds ptr, ptr %t245, i64 %t247
  store ptr %t248, ptr %t249, align 8
  %t250 = load i32, ptr %nexpr.addr.168, align 4
  %t251 = add nsw i32 %t250, 1
  store i32 %t251, ptr %nexpr.addr.168, align 4
  br label %cond.end26
cond.end26:
  %t252 = load i32, ptr %bi.addr.169, align 4
  %t253 = add nsw i32 %t252, 1
  store i32 %t253, ptr %bi.addr.169, align 4
  br label %while.cond14
while.end14:
  %t255 = getelementptr inbounds [24 x i8], ptr @.str.484, i64 0, i64 0
  %t256 = load i32, ptr @g-ct-id, align 4
  %t257 = sext i32 %t256 to i64
  %t258 = call ptr @fmt-i64(ptr %t255, i64 %t257)
  store ptr %t258, ptr %ct-sym.addr.254, align 8
  %t259 = load i32, ptr @g-ct-id, align 4
  %t260 = add nsw i32 %t259, 1
  store i32 %t260, ptr @g-ct-id, align 4
  %t261 = load ptr, ptr %ct-def.addr.28, align 8
  store ptr %t261, ptr @g-out, align 8
  call void @reset-function-state()
  %t263 = load ptr, ptr @g-globals, align 8
  %t264 = call ptr @scope-new(ptr %t263)
  store ptr %t264, ptr %fn-scope.addr.262, align 8
  store i32 0, ptr %ei.addr.265, align 4
  br label %while.cond28
while.cond28:
  %t266 = load i32, ptr %ei.addr.265, align 4
  %t267 = load i32, ptr %nexpr.addr.168, align 4
  %t268 = icmp slt i32 %t266, %t267
  br i1 %t268, label %while.body28, label %while.end28
while.body28:
  %t269 = load ptr, ptr %expr-forms.addr.163, align 8
  %t270 = load i32, ptr %ei.addr.265, align 4
  %t271 = sext i32 %t270 to i64
  %t272 = getelementptr inbounds ptr, ptr %t269, i64 %t271
  %t273 = load ptr, ptr %t272, align 8
  %t274 = load ptr, ptr %fn-scope.addr.262, align 8
  %t275 = call ptr @emit-node(ptr %t273, ptr %t274)
  %t276 = load i32, ptr %ei.addr.265, align 4
  %t277 = add nsw i32 %t276, 1
  store i32 %t277, ptr %ei.addr.265, align 4
  br label %while.cond28
while.end28:
  %t278 = load i32, ptr @g-block-term, align 4
  %t279 = icmp eq i32 %t278, 0
  br i1 %t279, label %cond.then29.0, label %cond.end29
cond.then29.0:
  %t280 = load ptr, ptr @g-body-stream, align 8
  %t281 = getelementptr inbounds [12 x i8], ptr @.str.485, i64 0, i64 0
  %t282 = call i32 (ptr, ptr, ...) @fprintf(ptr %t280, ptr %t281)
  br label %cond.end29
cond.end29:
  %t283 = load ptr, ptr @g-entry-stream, align 8
  %t284 = call i32 @fclose(ptr %t283)
  %t285 = load ptr, ptr @g-body-stream, align 8
  %t286 = call i32 @fclose(ptr %t285)
  %t287 = load ptr, ptr %ct-def.addr.28, align 8
  %t288 = getelementptr inbounds [21 x i8], ptr @.str.486, i64 0, i64 0
  %t289 = load ptr, ptr %ct-sym.addr.254, align 8
  %t290 = call i32 (ptr, ptr, ...) @fprintf(ptr %t287, ptr %t288, ptr %t289)
  %t291 = load ptr, ptr %ct-def.addr.28, align 8
  %t292 = getelementptr inbounds [8 x i8], ptr @.str.487, i64 0, i64 0
  %t293 = call i32 (ptr, ptr, ...) @fprintf(ptr %t291, ptr %t292)
  %t294 = load ptr, ptr @g-entry-bufp, align 8
  %t295 = icmp ne ptr %t294, null
  store i1 %t295, ptr %and.val31, align 1
  br i1 %t295, label %and.rhs31, label %and.end31
and.rhs31:
  %t296 = load ptr, ptr @g-entry-bufp, align 8
  %t297 = sext i32 0 to i64
  %t298 = call i32 @char-at(ptr %t296, i64 %t297)
  %t299 = icmp ne i32 %t298, 0
  store i1 %t299, ptr %and.val31, align 1
  br label %and.end31
and.end31:
  %t300 = load i1, ptr %and.val31, align 1
  br i1 %t300, label %cond.then30.0, label %cond.end30
cond.then30.0:
  %t301 = load ptr, ptr @g-entry-bufp, align 8
  %t302 = load ptr, ptr %ct-def.addr.28, align 8
  %t303 = call i32 @fputs(ptr %t301, ptr %t302)
  br label %cond.end30
cond.end30:
  %t304 = load ptr, ptr @g-body-bufp, align 8
  %t305 = icmp ne ptr %t304, null
  store i1 %t305, ptr %and.val33, align 1
  br i1 %t305, label %and.rhs33, label %and.end33
and.rhs33:
  %t306 = load ptr, ptr @g-body-bufp, align 8
  %t307 = sext i32 0 to i64
  %t308 = call i32 @char-at(ptr %t306, i64 %t307)
  %t309 = icmp ne i32 %t308, 0
  store i1 %t309, ptr %and.val33, align 1
  br label %and.end33
and.end33:
  %t310 = load i1, ptr %and.val33, align 1
  br i1 %t310, label %cond.then32.0, label %cond.end32
cond.then32.0:
  %t311 = load ptr, ptr @g-body-bufp, align 8
  %t312 = load ptr, ptr %ct-def.addr.28, align 8
  %t313 = call i32 @fputs(ptr %t311, ptr %t312)
  br label %cond.end32
cond.end32:
  %t314 = load ptr, ptr %ct-def.addr.28, align 8
  %t315 = getelementptr inbounds [4 x i8], ptr @.str.488, i64 0, i64 0
  %t316 = call i32 (ptr, ptr, ...) @fprintf(ptr %t314, ptr %t315)
  %t317 = load ptr, ptr @g-entry-bufp, align 8
  call void @free(ptr %t317)
  %t318 = load ptr, ptr @g-body-bufp, align 8
  call void @free(ptr %t318)
  store ptr null, ptr @g-entry-bufp, align 8
  store ptr null, ptr @g-body-bufp, align 8
  %t320 = load i32, ptr @g-qq-used, align 4
  store i32 %t320, ptr %ct-qq.addr.319, align 4
  %t321 = load ptr, ptr %saved-g-out.addr.30, align 8
  store ptr %t321, ptr @g-out, align 8
  %t322 = load ptr, ptr %saved-decl-out.addr.32, align 8
  store ptr %t322, ptr @g-decl-out, align 8
  %t323 = load i32, ptr %saved-qq-used.addr.34, align 4
  store i32 %t323, ptr @g-qq-used, align 4
  %t324 = load i32, ptr %ct-qq.addr.319, align 4
  %t325 = icmp ne i32 %t324, 0
  br i1 %t325, label %cond.then34.0, label %cond.end34
cond.then34.0:
  %t326 = load ptr, ptr %ct-decl.addr.26, align 8
  %t327 = getelementptr inbounds [26 x i8], ptr @.str.489, i64 0, i64 0
  %t328 = call i32 (ptr, ptr, ...) @fprintf(ptr %t326, ptr %t327)
  %t329 = load ptr, ptr %ct-def.addr.28, align 8
  %t330 = getelementptr inbounds [48 x i8], ptr @.str.490, i64 0, i64 0
  %t331 = call i32 (ptr, ptr, ...) @fprintf(ptr %t329, ptr %t330)
  %t332 = load ptr, ptr %ct-def.addr.28, align 8
  %t333 = getelementptr inbounds [34 x i8], ptr @.str.491, i64 0, i64 0
  %t334 = call i32 (ptr, ptr, ...) @fprintf(ptr %t332, ptr %t333)
  %t335 = load ptr, ptr %ct-def.addr.28, align 8
  %t336 = getelementptr inbounds [89 x i8], ptr @.str.492, i64 0, i64 0
  %t337 = call i32 (ptr, ptr, ...) @fprintf(ptr %t335, ptr %t336)
  %t338 = load ptr, ptr %ct-def.addr.28, align 8
  %t339 = getelementptr inbounds [34 x i8], ptr @.str.493, i64 0, i64 0
  %t340 = call i32 (ptr, ptr, ...) @fprintf(ptr %t338, ptr %t339)
  %t341 = load ptr, ptr %ct-def.addr.28, align 8
  %t342 = getelementptr inbounds [89 x i8], ptr @.str.494, i64 0, i64 0
  %t343 = call i32 (ptr, ptr, ...) @fprintf(ptr %t341, ptr %t342)
  %t344 = load ptr, ptr %ct-def.addr.28, align 8
  %t345 = getelementptr inbounds [36 x i8], ptr @.str.495, i64 0, i64 0
  %t346 = call i32 (ptr, ptr, ...) @fprintf(ptr %t344, ptr %t345)
  %t347 = load ptr, ptr %ct-def.addr.28, align 8
  %t348 = getelementptr inbounds [89 x i8], ptr @.str.496, i64 0, i64 0
  %t349 = call i32 (ptr, ptr, ...) @fprintf(ptr %t347, ptr %t348)
  %t350 = load ptr, ptr %ct-def.addr.28, align 8
  %t351 = getelementptr inbounds [36 x i8], ptr @.str.497, i64 0, i64 0
  %t352 = call i32 (ptr, ptr, ...) @fprintf(ptr %t350, ptr %t351)
  %t353 = load ptr, ptr %ct-def.addr.28, align 8
  %t354 = getelementptr inbounds [15 x i8], ptr @.str.498, i64 0, i64 0
  %t355 = call i32 (ptr, ptr, ...) @fprintf(ptr %t353, ptr %t354)
  %t356 = load ptr, ptr %ct-def.addr.28, align 8
  %t357 = getelementptr inbounds [4 x i8], ptr @.str.499, i64 0, i64 0
  %t358 = call i32 (ptr, ptr, ...) @fprintf(ptr %t356, ptr %t357)
  %t359 = load ptr, ptr %ct-def.addr.28, align 8
  %t360 = getelementptr inbounds [50 x i8], ptr @.str.500, i64 0, i64 0
  %t361 = call i32 (ptr, ptr, ...) @fprintf(ptr %t359, ptr %t360)
  %t362 = load ptr, ptr %ct-def.addr.28, align 8
  %t363 = getelementptr inbounds [8 x i8], ptr @.str.501, i64 0, i64 0
  %t364 = call i32 (ptr, ptr, ...) @fprintf(ptr %t362, ptr %t363)
  %t365 = load ptr, ptr %ct-def.addr.28, align 8
  %t366 = getelementptr inbounds [31 x i8], ptr @.str.502, i64 0, i64 0
  %t367 = call i32 (ptr, ptr, ...) @fprintf(ptr %t365, ptr %t366)
  %t368 = load ptr, ptr %ct-def.addr.28, align 8
  %t369 = getelementptr inbounds [39 x i8], ptr @.str.503, i64 0, i64 0
  %t370 = call i32 (ptr, ptr, ...) @fprintf(ptr %t368, ptr %t369)
  %t371 = load ptr, ptr %ct-def.addr.28, align 8
  %t372 = getelementptr inbounds [6 x i8], ptr @.str.504, i64 0, i64 0
  %t373 = call i32 (ptr, ptr, ...) @fprintf(ptr %t371, ptr %t372)
  %t374 = load ptr, ptr %ct-def.addr.28, align 8
  %t375 = getelementptr inbounds [15 x i8], ptr @.str.505, i64 0, i64 0
  %t376 = call i32 (ptr, ptr, ...) @fprintf(ptr %t374, ptr %t375)
  %t377 = load ptr, ptr %ct-def.addr.28, align 8
  %t378 = getelementptr inbounds [6 x i8], ptr @.str.506, i64 0, i64 0
  %t379 = call i32 (ptr, ptr, ...) @fprintf(ptr %t377, ptr %t378)
  %t380 = load ptr, ptr %ct-def.addr.28, align 8
  %t381 = getelementptr inbounds [89 x i8], ptr @.str.507, i64 0, i64 0
  %t382 = call i32 (ptr, ptr, ...) @fprintf(ptr %t380, ptr %t381)
  %t383 = load ptr, ptr %ct-def.addr.28, align 8
  %t384 = getelementptr inbounds [39 x i8], ptr @.str.508, i64 0, i64 0
  %t385 = call i32 (ptr, ptr, ...) @fprintf(ptr %t383, ptr %t384)
  %t386 = load ptr, ptr %ct-def.addr.28, align 8
  %t387 = getelementptr inbounds [89 x i8], ptr @.str.509, i64 0, i64 0
  %t388 = call i32 (ptr, ptr, ...) @fprintf(ptr %t386, ptr %t387)
  %t389 = load ptr, ptr %ct-def.addr.28, align 8
  %t390 = getelementptr inbounds [39 x i8], ptr @.str.510, i64 0, i64 0
  %t391 = call i32 (ptr, ptr, ...) @fprintf(ptr %t389, ptr %t390)
  %t392 = load ptr, ptr %ct-def.addr.28, align 8
  %t393 = getelementptr inbounds [51 x i8], ptr @.str.511, i64 0, i64 0
  %t394 = call i32 (ptr, ptr, ...) @fprintf(ptr %t392, ptr %t393)
  %t395 = load ptr, ptr %ct-def.addr.28, align 8
  %t396 = getelementptr inbounds [49 x i8], ptr @.str.512, i64 0, i64 0
  %t397 = call i32 (ptr, ptr, ...) @fprintf(ptr %t395, ptr %t396)
  %t398 = load ptr, ptr %ct-def.addr.28, align 8
  %t399 = getelementptr inbounds [15 x i8], ptr @.str.513, i64 0, i64 0
  %t400 = call i32 (ptr, ptr, ...) @fprintf(ptr %t398, ptr %t399)
  %t401 = load ptr, ptr %ct-def.addr.28, align 8
  %t402 = getelementptr inbounds [4 x i8], ptr @.str.514, i64 0, i64 0
  %t403 = call i32 (ptr, ptr, ...) @fprintf(ptr %t401, ptr %t402)
  br label %cond.end34
cond.end34:
  %t404 = load ptr, ptr %ct-type.addr.24, align 8
  %t405 = call i32 @fclose(ptr %t404)
  %t406 = load ptr, ptr %ct-decl.addr.26, align 8
  %t407 = call i32 @fclose(ptr %t406)
  %t408 = load ptr, ptr %ct-def.addr.28, align 8
  %t409 = call i32 @fclose(ptr %t408)
  store ptr null, ptr %ir-bufp.addr.410, align 8
  %t412 = sext i32 0 to i64
  store i64 %t412, ptr %ir-sizep.addr.411, align 8
  %t414 = call ptr @open_memstream(ptr %ir-bufp.addr.410, ptr %ir-sizep.addr.411)
  store ptr %t414, ptr %irs.addr.413, align 8
  %t415 = load ptr, ptr %irs.addr.413, align 8
  %t416 = getelementptr inbounds [31 x i8], ptr @.str.515, i64 0, i64 0
  %t417 = call i32 (ptr, ptr, ...) @fprintf(ptr %t415, ptr %t416)
  %t418 = load ptr, ptr %irs.addr.413, align 8
  %t419 = getelementptr inbounds [40 x i8], ptr @.str.516, i64 0, i64 0
  %t420 = call i32 (ptr, ptr, ...) @fprintf(ptr %t418, ptr %t419)
  %t421 = load ptr, ptr @g-type-bufp, align 8
  %t422 = icmp ne ptr %t421, null
  store i1 %t422, ptr %and.val36, align 1
  br i1 %t422, label %and.rhs36, label %and.end36
and.rhs36:
  %t423 = load ptr, ptr @g-type-bufp, align 8
  %t424 = sext i32 0 to i64
  %t425 = call i32 @char-at(ptr %t423, i64 %t424)
  %t426 = icmp ne i32 %t425, 0
  store i1 %t426, ptr %and.val36, align 1
  br label %and.end36
and.end36:
  %t427 = load i1, ptr %and.val36, align 1
  br i1 %t427, label %cond.then35.0, label %cond.end35
cond.then35.0:
  %t428 = load ptr, ptr @g-type-bufp, align 8
  %t429 = load ptr, ptr %irs.addr.413, align 8
  %t430 = call i32 @fputs(ptr %t428, ptr %t429)
  br label %cond.end35
cond.end35:
  %t431 = load ptr, ptr %ct-type-bufp.addr.15, align 8
  %t432 = icmp ne ptr %t431, null
  store i1 %t432, ptr %and.val38, align 1
  br i1 %t432, label %and.rhs38, label %and.end38
and.rhs38:
  %t433 = load ptr, ptr %ct-type-bufp.addr.15, align 8
  %t434 = sext i32 0 to i64
  %t435 = call i32 @char-at(ptr %t433, i64 %t434)
  %t436 = icmp ne i32 %t435, 0
  store i1 %t436, ptr %and.val38, align 1
  br label %and.end38
and.end38:
  %t437 = load i1, ptr %and.val38, align 1
  br i1 %t437, label %cond.then37.0, label %cond.end37
cond.then37.0:
  %t438 = load ptr, ptr %ct-type-bufp.addr.15, align 8
  %t439 = load ptr, ptr %irs.addr.413, align 8
  %t440 = call i32 @fputs(ptr %t438, ptr %t439)
  br label %cond.end37
cond.end37:
  %t441 = load ptr, ptr %irs.addr.413, align 8
  call void @emit-string-table(ptr %t441)
  %t442 = load ptr, ptr @g-decl-bufp, align 8
  %t443 = icmp ne ptr %t442, null
  store i1 %t443, ptr %and.val40, align 1
  br i1 %t443, label %and.rhs40, label %and.end40
and.rhs40:
  %t444 = load ptr, ptr @g-decl-bufp, align 8
  %t445 = sext i32 0 to i64
  %t446 = call i32 @char-at(ptr %t444, i64 %t445)
  %t447 = icmp ne i32 %t446, 0
  store i1 %t447, ptr %and.val40, align 1
  br label %and.end40
and.end40:
  %t448 = load i1, ptr %and.val40, align 1
  br i1 %t448, label %cond.then39.0, label %cond.end39
cond.then39.0:
  %t449 = load ptr, ptr @g-decl-bufp, align 8
  %t450 = load ptr, ptr %irs.addr.413, align 8
  %t451 = call i32 @fputs(ptr %t449, ptr %t450)
  br label %cond.end39
cond.end39:
  %t452 = load ptr, ptr %ct-decl-bufp.addr.18, align 8
  %t453 = icmp ne ptr %t452, null
  store i1 %t453, ptr %and.val42, align 1
  br i1 %t453, label %and.rhs42, label %and.end42
and.rhs42:
  %t454 = load ptr, ptr %ct-decl-bufp.addr.18, align 8
  %t455 = sext i32 0 to i64
  %t456 = call i32 @char-at(ptr %t454, i64 %t455)
  %t457 = icmp ne i32 %t456, 0
  store i1 %t457, ptr %and.val42, align 1
  br label %and.end42
and.end42:
  %t458 = load i1, ptr %and.val42, align 1
  br i1 %t458, label %cond.then41.0, label %cond.end41
cond.then41.0:
  %t459 = load ptr, ptr %ct-decl-bufp.addr.18, align 8
  %t460 = load ptr, ptr %irs.addr.413, align 8
  %t461 = call i32 @fputs(ptr %t459, ptr %t460)
  br label %cond.end41
cond.end41:
  %t462 = load ptr, ptr %ct-def-bufp.addr.21, align 8
  %t463 = icmp ne ptr %t462, null
  store i1 %t463, ptr %and.val44, align 1
  br i1 %t463, label %and.rhs44, label %and.end44
and.rhs44:
  %t464 = load ptr, ptr %ct-def-bufp.addr.21, align 8
  %t465 = sext i32 0 to i64
  %t466 = call i32 @char-at(ptr %t464, i64 %t465)
  %t467 = icmp ne i32 %t466, 0
  store i1 %t467, ptr %and.val44, align 1
  br label %and.end44
and.end44:
  %t468 = load i1, ptr %and.val44, align 1
  br i1 %t468, label %cond.then43.0, label %cond.end43
cond.then43.0:
  %t469 = load ptr, ptr %ct-def-bufp.addr.21, align 8
  %t470 = load ptr, ptr %irs.addr.413, align 8
  %t471 = call i32 @fputs(ptr %t469, ptr %t470)
  br label %cond.end43
cond.end43:
  %t472 = load ptr, ptr %irs.addr.413, align 8
  %t473 = call i32 @fclose(ptr %t472)
  %t474 = load ptr, ptr %ir-bufp.addr.410, align 8
  %t475 = load ptr, ptr %ff.addr.3, align 8
  %t476 = getelementptr inbounds %Node, ptr %t475, i32 0, i32 1
  %t477 = load i32, ptr %t476, align 4
  call void @jit-add-module(ptr %t474, i32 %t477)
  %t478 = load ptr, ptr %ff.addr.3, align 8
  %t479 = getelementptr inbounds %Node, ptr %t478, i32 0, i32 1
  %t480 = load i32, ptr %t479, align 4
  %t481 = load ptr, ptr %ct-sym.addr.254, align 8
  call void @jit-call-ct-main-sym(i32 %t480, ptr %t481)
  %t482 = load ptr, ptr %ct-type-bufp.addr.15, align 8
  call void @free(ptr %t482)
  %t483 = load ptr, ptr %ct-decl-bufp.addr.18, align 8
  call void @free(ptr %t483)
  %t484 = load ptr, ptr %ct-def-bufp.addr.21, align 8
  call void @free(ptr %t484)
  %t485 = load ptr, ptr %ir-bufp.addr.410, align 8
  call void @free(ptr %t485)
  ret void
}

define void @emit-defmacro(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %ff.addr.0 = alloca ptr, align 8
  %name-node.addr.9 = alloca ptr, align 8
  %params-node.addr.12 = alloca ptr, align 8
  %macro-name.addr.30 = alloca ptr, align 8
  %num-params.addr.34 = alloca i32, align 4
  %jit-name.addr.37 = alloca ptr, align 8
  %variadic.addr.42 = alloca i32, align 4
  %pcount.addr.43 = alloca i32, align 4
  %vi.addr.45 = alloca i32, align 4
  %vp.addr.49 = alloca ptr, align 8
  %pnames.addr.71 = alloca ptr, align 8
  %pi.addr.72 = alloca i32, align 4
  %ai.addr.73 = alloca i32, align 4
  %p.addr.84 = alloca ptr, align 8
  %mdef.addr.119 = alloca ptr, align 8
  %ct-decl-bufp.addr.142 = alloca ptr, align 8
  %ct-decl-sizep.addr.143 = alloca i64, align 8
  %ct-def-bufp.addr.145 = alloca ptr, align 8
  %ct-def-sizep.addr.146 = alloca i64, align 8
  %ct-decl.addr.148 = alloca ptr, align 8
  %ct-def.addr.150 = alloca ptr, align 8
  %saved-g-out.addr.152 = alloca ptr, align 8
  %saved-decl-out.addr.154 = alloca ptr, align 8
  %saved-qq-used.addr.156 = alloca i32, align 4
  %fn-scope.addr.160 = alloca ptr, align 8
  %ei.addr.169 = alloca i32, align 4
  %pname.addr.173 = alloca ptr, align 8
  %last-val.addr.212 = alloca ptr, align 8
  %bi.addr.214 = alloca i32, align 4
  %bv.addr.219 = alloca ptr, align 8
  %and.val14 = alloca i1, align 1
  %and.val15 = alloca i1, align 1
  %macro-qq.addr.248 = alloca i32, align 4
  %and.val17 = alloca i1, align 1
  %and.val19 = alloca i1, align 1
  %ir-bufp.addr.396 = alloca ptr, align 8
  %ir-sizep.addr.397 = alloca i64, align 8
  %irs.addr.399 = alloca ptr, align 8
  %and.val23 = alloca i1, align 1
  %and.val25 = alloca i1, align 1
  %and.val27 = alloca i1, align 1
  %and.val29 = alloca i1, align 1
  %t1 = load ptr, ptr %form.addr, align 8
  store ptr %t1, ptr %ff.addr.0, align 8
  %t2 = load ptr, ptr %ff.addr.0, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp slt i32 %t3, 4
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %ff.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [41 x i8], ptr @.str.517, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %ff.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %name-node.addr.9, align 8
  %t13 = load ptr, ptr %ff.addr.0, align 8
  %t14 = call ptr @node-at(ptr %t13, i32 2)
  store ptr %t14, ptr %params-node.addr.12, align 8
  %t15 = load ptr, ptr %name-node.addr.9, align 8
  %t16 = getelementptr inbounds %Node, ptr %t15, i32 0, i32 0
  %t17 = load i32, ptr %t16, align 4
  %t18 = icmp ne i32 %t17, 2
  br i1 %t18, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t19 = load ptr, ptr %name-node.addr.9, align 8
  %t20 = getelementptr inbounds %Node, ptr %t19, i32 0, i32 1
  %t21 = load i32, ptr %t20, align 4
  %t22 = getelementptr inbounds [30 x i8], ptr @.str.518, i64 0, i64 0
  call void @die-at(i32 %t21, ptr %t22)
  br label %cond.end1
cond.end1:
  %t23 = load ptr, ptr %params-node.addr.12, align 8
  %t24 = call i32 @node-is-list(ptr %t23)
  %t25 = icmp eq i32 %t24, 0
  br i1 %t25, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t26 = load ptr, ptr %name-node.addr.9, align 8
  %t27 = getelementptr inbounds %Node, ptr %t26, i32 0, i32 1
  %t28 = load i32, ptr %t27, align 4
  %t29 = getelementptr inbounds [32 x i8], ptr @.str.519, i64 0, i64 0
  call void @die-at(i32 %t28, ptr %t29)
  br label %cond.end2
cond.end2:
  %t31 = load ptr, ptr %name-node.addr.9, align 8
  %t32 = getelementptr inbounds %Node, ptr %t31, i32 0, i32 3
  %t33 = load ptr, ptr %t32, align 8
  store ptr %t33, ptr %macro-name.addr.30, align 8
  %t35 = load ptr, ptr %params-node.addr.12, align 8
  %t36 = call i32 @node-len(ptr %t35)
  store i32 %t36, ptr %num-params.addr.34, align 4
  %t38 = getelementptr inbounds [11 x i8], ptr @.str.520, i64 0, i64 0
  %t39 = load ptr, ptr %macro-name.addr.30, align 8
  %t40 = call ptr @sanitize-for-ir(ptr %t39)
  %t41 = call ptr @fmt-s(ptr %t38, ptr %t40)
  store ptr %t41, ptr %jit-name.addr.37, align 8
  store i32 0, ptr %variadic.addr.42, align 4
  %t44 = load i32, ptr %num-params.addr.34, align 4
  store i32 %t44, ptr %pcount.addr.43, align 4
  store i32 0, ptr %vi.addr.45, align 4
  br label %while.cond3
while.cond3:
  %t46 = load i32, ptr %vi.addr.45, align 4
  %t47 = load i32, ptr %num-params.addr.34, align 4
  %t48 = icmp slt i32 %t46, %t47
  br i1 %t48, label %while.body3, label %while.end3
while.body3:
  %t50 = load ptr, ptr %params-node.addr.12, align 8
  %t51 = load i32, ptr %vi.addr.45, align 4
  %t52 = call ptr @node-at(ptr %t50, i32 %t51)
  store ptr %t52, ptr %vp.addr.49, align 8
  %t53 = load ptr, ptr %vp.addr.49, align 8
  %t54 = getelementptr inbounds %Node, ptr %t53, i32 0, i32 3
  %t55 = load ptr, ptr %t54, align 8
  %t56 = getelementptr inbounds [6 x i8], ptr @.str.521, i64 0, i64 0
  %t57 = call i32 @strcmp(ptr %t55, ptr %t56)
  %t58 = icmp eq i32 %t57, 0
  br i1 %t58, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t59 = load i32, ptr %vi.addr.45, align 4
  %t60 = load i32, ptr %num-params.addr.34, align 4
  %t61 = sub nsw i32 %t60, 2
  %t62 = icmp ne i32 %t59, %t61
  br i1 %t62, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t63 = load ptr, ptr %vp.addr.49, align 8
  %t64 = getelementptr inbounds %Node, ptr %t63, i32 0, i32 1
  %t65 = load i32, ptr %t64, align 4
  %t66 = getelementptr inbounds [45 x i8], ptr @.str.522, i64 0, i64 0
  call void @die-at(i32 %t65, ptr %t66)
  br label %cond.end5
cond.end5:
  store i32 1, ptr %variadic.addr.42, align 4
  %t67 = load i32, ptr %num-params.addr.34, align 4
  %t68 = sub nsw i32 %t67, 1
  store i32 %t68, ptr %pcount.addr.43, align 4
  br label %cond.end4
cond.end4:
  %t69 = load i32, ptr %vi.addr.45, align 4
  %t70 = add nsw i32 %t69, 1
  store i32 %t70, ptr %vi.addr.45, align 4
  br label %while.cond3
while.end3:
  store ptr null, ptr %pnames.addr.71, align 8
  store i32 0, ptr %pi.addr.72, align 4
  store i32 0, ptr %ai.addr.73, align 4
  %t74 = load i32, ptr %pcount.addr.43, align 4
  %t75 = icmp sgt i32 %t74, 0
  br i1 %t75, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t76 = load i32, ptr %pcount.addr.43, align 4
  %t77 = call i64 @i64(i32 %t76)
  %t78 = call i64 @i64(i32 8)
  %t79 = mul nsw i64 %t77, %t78
  %t80 = call ptr @arena-alloc(i64 %t79)
  store ptr %t80, ptr %pnames.addr.71, align 8
  br label %cond.end6
cond.end6:
  br label %while.cond7
while.cond7:
  %t81 = load i32, ptr %pi.addr.72, align 4
  %t82 = load i32, ptr %num-params.addr.34, align 4
  %t83 = icmp slt i32 %t81, %t82
  br i1 %t83, label %while.body7, label %while.end7
while.body7:
  %t85 = load ptr, ptr %params-node.addr.12, align 8
  %t86 = load i32, ptr %pi.addr.72, align 4
  %t87 = call ptr @node-at(ptr %t85, i32 %t86)
  store ptr %t87, ptr %p.addr.84, align 8
  %t88 = load ptr, ptr %p.addr.84, align 8
  %t89 = getelementptr inbounds %Node, ptr %t88, i32 0, i32 0
  %t90 = load i32, ptr %t89, align 4
  %t91 = icmp ne i32 %t90, 2
  br i1 %t91, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t92 = load ptr, ptr %p.addr.84, align 8
  %t93 = getelementptr inbounds %Node, ptr %t92, i32 0, i32 1
  %t94 = load i32, ptr %t93, align 4
  %t95 = getelementptr inbounds [33 x i8], ptr @.str.523, i64 0, i64 0
  call void @die-at(i32 %t94, ptr %t95)
  br label %cond.end8
cond.end8:
  %t96 = load ptr, ptr %p.addr.84, align 8
  %t97 = getelementptr inbounds %Node, ptr %t96, i32 0, i32 3
  %t98 = load ptr, ptr %t97, align 8
  %t99 = getelementptr inbounds [6 x i8], ptr @.str.524, i64 0, i64 0
  %t100 = call i32 @strcmp(ptr %t98, ptr %t99)
  %t101 = icmp ne i32 %t100, 0
  br i1 %t101, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t102 = load ptr, ptr %pnames.addr.71, align 8
  %t103 = load i32, ptr %ai.addr.73, align 4
  %t104 = sext i32 %t103 to i64
  %t105 = load ptr, ptr %p.addr.84, align 8
  %t106 = getelementptr inbounds %Node, ptr %t105, i32 0, i32 3
  %t107 = load ptr, ptr %t106, align 8
  %t108 = getelementptr inbounds ptr, ptr %t102, i64 %t104
  store ptr %t107, ptr %t108, align 8
  %t109 = load i32, ptr %ai.addr.73, align 4
  %t110 = add nsw i32 %t109, 1
  store i32 %t110, ptr %ai.addr.73, align 4
  br label %cond.end9
cond.end9:
  %t111 = load i32, ptr %pi.addr.72, align 4
  %t112 = add nsw i32 %t111, 1
  store i32 %t112, ptr %pi.addr.72, align 4
  br label %while.cond7
while.end7:
  %t113 = load i32, ptr @g-num-macros, align 4
  %t114 = icmp sge i32 %t113, 256
  br i1 %t114, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t115 = load ptr, ptr %ff.addr.0, align 8
  %t116 = getelementptr inbounds %Node, ptr %t115, i32 0, i32 1
  %t117 = load i32, ptr %t116, align 4
  %t118 = getelementptr inbounds [27 x i8], ptr @.str.525, i64 0, i64 0
  call void @die-at(i32 %t117, ptr %t118)
  br label %cond.end10
cond.end10:
  %t120 = load ptr, ptr @g-macros, align 8
  %t121 = load i32, ptr @g-num-macros, align 4
  %t122 = sext i32 %t121 to i64
  %t123 = getelementptr inbounds %MacroDef, ptr %t120, i64 %t122
  store ptr %t123, ptr %mdef.addr.119, align 8
  %t124 = load ptr, ptr %mdef.addr.119, align 8
  %t125 = load ptr, ptr %macro-name.addr.30, align 8
  %t126 = getelementptr inbounds %MacroDef, ptr %t124, i32 0, i32 0
  store ptr %t125, ptr %t126, align 8
  %t127 = load ptr, ptr %mdef.addr.119, align 8
  %t128 = load ptr, ptr %jit-name.addr.37, align 8
  %t129 = getelementptr inbounds %MacroDef, ptr %t127, i32 0, i32 1
  store ptr %t128, ptr %t129, align 8
  %t130 = load ptr, ptr %mdef.addr.119, align 8
  %t131 = load i32, ptr %pcount.addr.43, align 4
  %t132 = getelementptr inbounds %MacroDef, ptr %t130, i32 0, i32 2
  store i32 %t131, ptr %t132, align 4
  %t133 = load ptr, ptr %mdef.addr.119, align 8
  %t134 = load i32, ptr %variadic.addr.42, align 4
  %t135 = getelementptr inbounds %MacroDef, ptr %t133, i32 0, i32 3
  store i32 %t134, ptr %t135, align 4
  %t136 = load i32, ptr @g-num-macros, align 4
  %t137 = add nsw i32 %t136, 1
  store i32 %t137, ptr @g-num-macros, align 4
  %t138 = load ptr, ptr @g-type-stream, align 8
  %t139 = call i32 @fflush(ptr %t138)
  %t140 = load ptr, ptr @g-decl-stream, align 8
  %t141 = call i32 @fflush(ptr %t140)
  store ptr null, ptr %ct-decl-bufp.addr.142, align 8
  %t144 = sext i32 0 to i64
  store i64 %t144, ptr %ct-decl-sizep.addr.143, align 8
  store ptr null, ptr %ct-def-bufp.addr.145, align 8
  %t147 = sext i32 0 to i64
  store i64 %t147, ptr %ct-def-sizep.addr.146, align 8
  %t149 = call ptr @open_memstream(ptr %ct-decl-bufp.addr.142, ptr %ct-decl-sizep.addr.143)
  store ptr %t149, ptr %ct-decl.addr.148, align 8
  %t151 = call ptr @open_memstream(ptr %ct-def-bufp.addr.145, ptr %ct-def-sizep.addr.146)
  store ptr %t151, ptr %ct-def.addr.150, align 8
  %t153 = load ptr, ptr @g-out, align 8
  store ptr %t153, ptr %saved-g-out.addr.152, align 8
  %t155 = load ptr, ptr @g-decl-out, align 8
  store ptr %t155, ptr %saved-decl-out.addr.154, align 8
  %t157 = load i32, ptr @g-qq-used, align 4
  store i32 %t157, ptr %saved-qq-used.addr.156, align 4
  store i32 0, ptr @g-qq-used, align 4
  %t158 = load ptr, ptr %ct-decl.addr.148, align 8
  store ptr %t158, ptr @g-decl-out, align 8
  %t159 = load ptr, ptr %ct-def.addr.150, align 8
  store ptr %t159, ptr @g-out, align 8
  call void @reset-function-state()
  %t161 = load ptr, ptr @g-globals, align 8
  %t162 = call ptr @scope-new(ptr %t161)
  store ptr %t162, ptr %fn-scope.addr.160, align 8
  %t163 = load ptr, ptr @g-entry-stream, align 8
  %t164 = getelementptr inbounds [39 x i8], ptr @.str.526, i64 0, i64 0
  %t165 = call i32 (ptr, ptr, ...) @fprintf(ptr %t163, ptr %t164)
  %t166 = load ptr, ptr @g-entry-stream, align 8
  %t167 = getelementptr inbounds [54 x i8], ptr @.str.527, i64 0, i64 0
  %t168 = call i32 (ptr, ptr, ...) @fprintf(ptr %t166, ptr %t167)
  store i32 0, ptr %ei.addr.169, align 4
  br label %while.cond11
while.cond11:
  %t170 = load i32, ptr %ei.addr.169, align 4
  %t171 = load i32, ptr %pcount.addr.43, align 4
  %t172 = icmp slt i32 %t170, %t171
  br i1 %t172, label %while.body11, label %while.end11
while.body11:
  %t174 = load ptr, ptr %pnames.addr.71, align 8
  %t175 = load i32, ptr %ei.addr.169, align 4
  %t176 = sext i32 %t175 to i64
  %t177 = getelementptr inbounds ptr, ptr %t174, i64 %t176
  %t178 = load ptr, ptr %t177, align 8
  store ptr %t178, ptr %pname.addr.173, align 8
  %t179 = load ptr, ptr @g-entry-stream, align 8
  %t180 = getelementptr inbounds [35 x i8], ptr @.str.528, i64 0, i64 0
  %t181 = load ptr, ptr %pname.addr.173, align 8
  %t182 = call i32 (ptr, ptr, ...) @fprintf(ptr %t179, ptr %t180, ptr %t181)
  %t183 = load ptr, ptr @g-entry-stream, align 8
  %t184 = getelementptr inbounds [51 x i8], ptr @.str.529, i64 0, i64 0
  %t185 = load i32, ptr %ei.addr.169, align 4
  %t186 = call i32 (ptr, ptr, ...) @fprintf(ptr %t183, ptr %t184, i32 %t185)
  %t187 = load ptr, ptr @g-entry-stream, align 8
  %t188 = getelementptr inbounds [54 x i8], ptr @.str.530, i64 0, i64 0
  %t189 = load i32, ptr %ei.addr.169, align 4
  %t190 = load i32, ptr %ei.addr.169, align 4
  %t191 = load i32, ptr %ei.addr.169, align 4
  %t192 = call i32 (ptr, ptr, ...) @fprintf(ptr %t187, ptr %t188, i32 %t189, i32 %t190, i32 %t191)
  %t193 = load ptr, ptr @g-entry-stream, align 8
  %t194 = getelementptr inbounds [46 x i8], ptr @.str.531, i64 0, i64 0
  %t195 = load i32, ptr %ei.addr.169, align 4
  %t196 = load i32, ptr %ei.addr.169, align 4
  %t197 = call i32 (ptr, ptr, ...) @fprintf(ptr %t193, ptr %t194, i32 %t195, i32 %t196)
  %t198 = load ptr, ptr @g-entry-stream, align 8
  %t199 = getelementptr inbounds [46 x i8], ptr @.str.532, i64 0, i64 0
  %t200 = load i32, ptr %ei.addr.169, align 4
  %t201 = load ptr, ptr %pname.addr.173, align 8
  %t202 = call i32 (ptr, ptr, ...) @fprintf(ptr %t198, ptr %t199, i32 %t200, ptr %t201)
  %t203 = load ptr, ptr %fn-scope.addr.160, align 8
  %t204 = load ptr, ptr %pname.addr.173, align 8
  %t205 = load ptr, ptr @ty-ptr, align 8
  %t206 = getelementptr inbounds [10 x i8], ptr @.str.533, i64 0, i64 0
  %t207 = load ptr, ptr %pname.addr.173, align 8
  %t208 = call ptr @fmt-s(ptr %t206, ptr %t207)
  %t209 = call ptr @scope-define(ptr %t203, ptr %t204, ptr %t205, ptr %t208, i32 1)
  %t210 = load i32, ptr %ei.addr.169, align 4
  %t211 = add nsw i32 %t210, 1
  store i32 %t211, ptr %ei.addr.169, align 4
  br label %while.cond11
while.end11:
  %t213 = getelementptr inbounds [5 x i8], ptr @.str.534, i64 0, i64 0
  store ptr %t213, ptr %last-val.addr.212, align 8
  store i32 3, ptr %bi.addr.214, align 4
  br label %while.cond12
while.cond12:
  %t215 = load i32, ptr %bi.addr.214, align 4
  %t216 = load ptr, ptr %ff.addr.0, align 8
  %t217 = call i32 @node-len(ptr %t216)
  %t218 = icmp slt i32 %t215, %t217
  br i1 %t218, label %while.body12, label %while.end12
while.body12:
  %t220 = load ptr, ptr %ff.addr.0, align 8
  %t221 = load i32, ptr %bi.addr.214, align 4
  %t222 = call ptr @node-at(ptr %t220, i32 %t221)
  %t223 = load ptr, ptr %fn-scope.addr.160, align 8
  %t224 = call ptr @emit-node(ptr %t222, ptr %t223)
  store ptr %t224, ptr %bv.addr.219, align 8
  %t225 = load ptr, ptr %bv.addr.219, align 8
  %t226 = icmp ne ptr %t225, null
  store i1 %t226, ptr %and.val14, align 1
  br i1 %t226, label %and.rhs14, label %and.end14
and.rhs14:
  %t227 = load ptr, ptr %bv.addr.219, align 8
  %t228 = getelementptr inbounds %Val, ptr %t227, i32 0, i32 1
  %t229 = load ptr, ptr %t228, align 8
  %t230 = icmp ne ptr %t229, null
  store i1 %t230, ptr %and.val15, align 1
  br i1 %t230, label %and.rhs15, label %and.end15
and.rhs15:
  %t231 = load ptr, ptr %bv.addr.219, align 8
  %t232 = getelementptr inbounds %Val, ptr %t231, i32 0, i32 0
  %t233 = load ptr, ptr %t232, align 8
  %t234 = getelementptr inbounds %Type, ptr %t233, i32 0, i32 0
  %t235 = load i32, ptr %t234, align 4
  %t236 = icmp eq i32 %t235, 6
  store i1 %t236, ptr %and.val15, align 1
  br label %and.end15
and.end15:
  %t237 = load i1, ptr %and.val15, align 1
  store i1 %t237, ptr %and.val14, align 1
  br label %and.end14
and.end14:
  %t238 = load i1, ptr %and.val14, align 1
  br i1 %t238, label %cond.then13.0, label %cond.end13
cond.then13.0:
  %t239 = load ptr, ptr %bv.addr.219, align 8
  %t240 = getelementptr inbounds %Val, ptr %t239, i32 0, i32 1
  %t241 = load ptr, ptr %t240, align 8
  store ptr %t241, ptr %last-val.addr.212, align 8
  br label %cond.end13
cond.end13:
  %t242 = load i32, ptr %bi.addr.214, align 4
  %t243 = add nsw i32 %t242, 1
  store i32 %t243, ptr %bi.addr.214, align 4
  br label %while.cond12
while.end12:
  %t244 = load ptr, ptr @g-body-stream, align 8
  %t245 = getelementptr inbounds [14 x i8], ptr @.str.535, i64 0, i64 0
  %t246 = load ptr, ptr %last-val.addr.212, align 8
  %t247 = call i32 (ptr, ptr, ...) @fprintf(ptr %t244, ptr %t245, ptr %t246)
  %t249 = load i32, ptr @g-qq-used, align 4
  store i32 %t249, ptr %macro-qq.addr.248, align 4
  %t250 = load ptr, ptr %saved-g-out.addr.152, align 8
  store ptr %t250, ptr @g-out, align 8
  %t251 = load ptr, ptr %saved-decl-out.addr.154, align 8
  store ptr %t251, ptr @g-decl-out, align 8
  %t252 = load i32, ptr %saved-qq-used.addr.156, align 4
  store i32 %t252, ptr @g-qq-used, align 4
  %t253 = load ptr, ptr @g-entry-stream, align 8
  %t254 = call i32 @fclose(ptr %t253)
  %t255 = load ptr, ptr @g-body-stream, align 8
  %t256 = call i32 @fclose(ptr %t255)
  %t257 = load ptr, ptr %ct-def.addr.150, align 8
  %t258 = getelementptr inbounds [36 x i8], ptr @.str.536, i64 0, i64 0
  %t259 = load ptr, ptr %jit-name.addr.37, align 8
  %t260 = call i32 (ptr, ptr, ...) @fprintf(ptr %t257, ptr %t258, ptr %t259)
  %t261 = load ptr, ptr %ct-def.addr.150, align 8
  %t262 = getelementptr inbounds [8 x i8], ptr @.str.537, i64 0, i64 0
  %t263 = call i32 (ptr, ptr, ...) @fprintf(ptr %t261, ptr %t262)
  %t264 = load ptr, ptr @g-entry-bufp, align 8
  %t265 = icmp ne ptr %t264, null
  store i1 %t265, ptr %and.val17, align 1
  br i1 %t265, label %and.rhs17, label %and.end17
and.rhs17:
  %t266 = load ptr, ptr @g-entry-bufp, align 8
  %t267 = sext i32 0 to i64
  %t268 = call i32 @char-at(ptr %t266, i64 %t267)
  %t269 = icmp ne i32 %t268, 0
  store i1 %t269, ptr %and.val17, align 1
  br label %and.end17
and.end17:
  %t270 = load i1, ptr %and.val17, align 1
  br i1 %t270, label %cond.then16.0, label %cond.end16
cond.then16.0:
  %t271 = load ptr, ptr @g-entry-bufp, align 8
  %t272 = load ptr, ptr %ct-def.addr.150, align 8
  %t273 = call i32 @fputs(ptr %t271, ptr %t272)
  br label %cond.end16
cond.end16:
  %t274 = load ptr, ptr @g-body-bufp, align 8
  %t275 = icmp ne ptr %t274, null
  store i1 %t275, ptr %and.val19, align 1
  br i1 %t275, label %and.rhs19, label %and.end19
and.rhs19:
  %t276 = load ptr, ptr @g-body-bufp, align 8
  %t277 = sext i32 0 to i64
  %t278 = call i32 @char-at(ptr %t276, i64 %t277)
  %t279 = icmp ne i32 %t278, 0
  store i1 %t279, ptr %and.val19, align 1
  br label %and.end19
and.end19:
  %t280 = load i1, ptr %and.val19, align 1
  br i1 %t280, label %cond.then18.0, label %cond.end18
cond.then18.0:
  %t281 = load ptr, ptr @g-body-bufp, align 8
  %t282 = load ptr, ptr %ct-def.addr.150, align 8
  %t283 = call i32 @fputs(ptr %t281, ptr %t282)
  br label %cond.end18
cond.end18:
  %t284 = load ptr, ptr %ct-def.addr.150, align 8
  %t285 = getelementptr inbounds [4 x i8], ptr @.str.538, i64 0, i64 0
  %t286 = call i32 (ptr, ptr, ...) @fprintf(ptr %t284, ptr %t285)
  %t287 = load ptr, ptr @g-entry-bufp, align 8
  call void @free(ptr %t287)
  %t288 = load ptr, ptr @g-body-bufp, align 8
  call void @free(ptr %t288)
  store ptr null, ptr @g-entry-bufp, align 8
  store ptr null, ptr @g-body-bufp, align 8
  %t289 = load i32, ptr %macro-qq.addr.248, align 4
  %t290 = icmp ne i32 %t289, 0
  br i1 %t290, label %cond.then20.0, label %cond.end20
cond.then20.0:
  %t291 = load i32, ptr @g-malloc-decl-done, align 4
  %t292 = icmp eq i32 %t291, 0
  br i1 %t292, label %cond.then21.0, label %cond.end21
cond.then21.0:
  %t293 = load ptr, ptr %ct-decl.addr.148, align 8
  %t294 = getelementptr inbounds [26 x i8], ptr @.str.539, i64 0, i64 0
  %t295 = call i32 (ptr, ptr, ...) @fprintf(ptr %t293, ptr %t294)
  br label %cond.end21
cond.end21:
  %t296 = load ptr, ptr %ct-def.addr.150, align 8
  %t297 = getelementptr inbounds [48 x i8], ptr @.str.540, i64 0, i64 0
  %t298 = call i32 (ptr, ptr, ...) @fprintf(ptr %t296, ptr %t297)
  %t299 = load ptr, ptr %ct-def.addr.150, align 8
  %t300 = getelementptr inbounds [34 x i8], ptr @.str.541, i64 0, i64 0
  %t301 = call i32 (ptr, ptr, ...) @fprintf(ptr %t299, ptr %t300)
  %t302 = load ptr, ptr %ct-def.addr.150, align 8
  %t303 = getelementptr inbounds [89 x i8], ptr @.str.542, i64 0, i64 0
  %t304 = call i32 (ptr, ptr, ...) @fprintf(ptr %t302, ptr %t303)
  %t305 = load ptr, ptr %ct-def.addr.150, align 8
  %t306 = getelementptr inbounds [34 x i8], ptr @.str.543, i64 0, i64 0
  %t307 = call i32 (ptr, ptr, ...) @fprintf(ptr %t305, ptr %t306)
  %t308 = load ptr, ptr %ct-def.addr.150, align 8
  %t309 = getelementptr inbounds [89 x i8], ptr @.str.544, i64 0, i64 0
  %t310 = call i32 (ptr, ptr, ...) @fprintf(ptr %t308, ptr %t309)
  %t311 = load ptr, ptr %ct-def.addr.150, align 8
  %t312 = getelementptr inbounds [34 x i8], ptr @.str.545, i64 0, i64 0
  %t313 = call i32 (ptr, ptr, ...) @fprintf(ptr %t311, ptr %t312)
  %t314 = load ptr, ptr %ct-def.addr.150, align 8
  %t315 = getelementptr inbounds [89 x i8], ptr @.str.546, i64 0, i64 0
  %t316 = call i32 (ptr, ptr, ...) @fprintf(ptr %t314, ptr %t315)
  %t317 = load ptr, ptr %ct-def.addr.150, align 8
  %t318 = getelementptr inbounds [34 x i8], ptr @.str.547, i64 0, i64 0
  %t319 = call i32 (ptr, ptr, ...) @fprintf(ptr %t317, ptr %t318)
  %t320 = load ptr, ptr %ct-def.addr.150, align 8
  %t321 = getelementptr inbounds [89 x i8], ptr @.str.548, i64 0, i64 0
  %t322 = call i32 (ptr, ptr, ...) @fprintf(ptr %t320, ptr %t321)
  %t323 = load ptr, ptr %ct-def.addr.150, align 8
  %t324 = getelementptr inbounds [37 x i8], ptr @.str.549, i64 0, i64 0
  %t325 = call i32 (ptr, ptr, ...) @fprintf(ptr %t323, ptr %t324)
  %t326 = load ptr, ptr %ct-def.addr.150, align 8
  %t327 = getelementptr inbounds [89 x i8], ptr @.str.550, i64 0, i64 0
  %t328 = call i32 (ptr, ptr, ...) @fprintf(ptr %t326, ptr %t327)
  %t329 = load ptr, ptr %ct-def.addr.150, align 8
  %t330 = getelementptr inbounds [36 x i8], ptr @.str.551, i64 0, i64 0
  %t331 = call i32 (ptr, ptr, ...) @fprintf(ptr %t329, ptr %t330)
  %t332 = load ptr, ptr %ct-def.addr.150, align 8
  %t333 = getelementptr inbounds [89 x i8], ptr @.str.552, i64 0, i64 0
  %t334 = call i32 (ptr, ptr, ...) @fprintf(ptr %t332, ptr %t333)
  %t335 = load ptr, ptr %ct-def.addr.150, align 8
  %t336 = getelementptr inbounds [36 x i8], ptr @.str.553, i64 0, i64 0
  %t337 = call i32 (ptr, ptr, ...) @fprintf(ptr %t335, ptr %t336)
  %t338 = load ptr, ptr %ct-def.addr.150, align 8
  %t339 = getelementptr inbounds [15 x i8], ptr @.str.554, i64 0, i64 0
  %t340 = call i32 (ptr, ptr, ...) @fprintf(ptr %t338, ptr %t339)
  %t341 = load ptr, ptr %ct-def.addr.150, align 8
  %t342 = getelementptr inbounds [4 x i8], ptr @.str.555, i64 0, i64 0
  %t343 = call i32 (ptr, ptr, ...) @fprintf(ptr %t341, ptr %t342)
  %t344 = load ptr, ptr %ct-def.addr.150, align 8
  %t345 = getelementptr inbounds [50 x i8], ptr @.str.556, i64 0, i64 0
  %t346 = call i32 (ptr, ptr, ...) @fprintf(ptr %t344, ptr %t345)
  %t347 = load ptr, ptr %ct-def.addr.150, align 8
  %t348 = getelementptr inbounds [8 x i8], ptr @.str.557, i64 0, i64 0
  %t349 = call i32 (ptr, ptr, ...) @fprintf(ptr %t347, ptr %t348)
  %t350 = load ptr, ptr %ct-def.addr.150, align 8
  %t351 = getelementptr inbounds [31 x i8], ptr @.str.558, i64 0, i64 0
  %t352 = call i32 (ptr, ptr, ...) @fprintf(ptr %t350, ptr %t351)
  %t353 = load ptr, ptr %ct-def.addr.150, align 8
  %t354 = getelementptr inbounds [39 x i8], ptr @.str.559, i64 0, i64 0
  %t355 = call i32 (ptr, ptr, ...) @fprintf(ptr %t353, ptr %t354)
  %t356 = load ptr, ptr %ct-def.addr.150, align 8
  %t357 = getelementptr inbounds [6 x i8], ptr @.str.560, i64 0, i64 0
  %t358 = call i32 (ptr, ptr, ...) @fprintf(ptr %t356, ptr %t357)
  %t359 = load ptr, ptr %ct-def.addr.150, align 8
  %t360 = getelementptr inbounds [15 x i8], ptr @.str.561, i64 0, i64 0
  %t361 = call i32 (ptr, ptr, ...) @fprintf(ptr %t359, ptr %t360)
  %t362 = load ptr, ptr %ct-def.addr.150, align 8
  %t363 = getelementptr inbounds [6 x i8], ptr @.str.562, i64 0, i64 0
  %t364 = call i32 (ptr, ptr, ...) @fprintf(ptr %t362, ptr %t363)
  %t365 = load ptr, ptr %ct-def.addr.150, align 8
  %t366 = getelementptr inbounds [89 x i8], ptr @.str.563, i64 0, i64 0
  %t367 = call i32 (ptr, ptr, ...) @fprintf(ptr %t365, ptr %t366)
  %t368 = load ptr, ptr %ct-def.addr.150, align 8
  %t369 = getelementptr inbounds [39 x i8], ptr @.str.564, i64 0, i64 0
  %t370 = call i32 (ptr, ptr, ...) @fprintf(ptr %t368, ptr %t369)
  %t371 = load ptr, ptr %ct-def.addr.150, align 8
  %t372 = getelementptr inbounds [89 x i8], ptr @.str.565, i64 0, i64 0
  %t373 = call i32 (ptr, ptr, ...) @fprintf(ptr %t371, ptr %t372)
  %t374 = load ptr, ptr %ct-def.addr.150, align 8
  %t375 = getelementptr inbounds [39 x i8], ptr @.str.566, i64 0, i64 0
  %t376 = call i32 (ptr, ptr, ...) @fprintf(ptr %t374, ptr %t375)
  %t377 = load ptr, ptr %ct-def.addr.150, align 8
  %t378 = getelementptr inbounds [51 x i8], ptr @.str.567, i64 0, i64 0
  %t379 = call i32 (ptr, ptr, ...) @fprintf(ptr %t377, ptr %t378)
  %t380 = load ptr, ptr %ct-def.addr.150, align 8
  %t381 = getelementptr inbounds [49 x i8], ptr @.str.568, i64 0, i64 0
  %t382 = call i32 (ptr, ptr, ...) @fprintf(ptr %t380, ptr %t381)
  %t383 = load ptr, ptr %ct-def.addr.150, align 8
  %t384 = getelementptr inbounds [15 x i8], ptr @.str.569, i64 0, i64 0
  %t385 = call i32 (ptr, ptr, ...) @fprintf(ptr %t383, ptr %t384)
  %t386 = load ptr, ptr %ct-def.addr.150, align 8
  %t387 = getelementptr inbounds [4 x i8], ptr @.str.570, i64 0, i64 0
  %t388 = call i32 (ptr, ptr, ...) @fprintf(ptr %t386, ptr %t387)
  br label %cond.end20
cond.end20:
  %t389 = load ptr, ptr %ct-decl.addr.148, align 8
  %t390 = getelementptr inbounds [31 x i8], ptr @.str.571, i64 0, i64 0
  %t391 = call i32 (ptr, ptr, ...) @fprintf(ptr %t389, ptr %t390)
  %t392 = load ptr, ptr %ct-decl.addr.148, align 8
  %t393 = call i32 @fclose(ptr %t392)
  %t394 = load ptr, ptr %ct-def.addr.150, align 8
  %t395 = call i32 @fclose(ptr %t394)
  store ptr null, ptr %ir-bufp.addr.396, align 8
  %t398 = sext i32 0 to i64
  store i64 %t398, ptr %ir-sizep.addr.397, align 8
  %t400 = call ptr @open_memstream(ptr %ir-bufp.addr.396, ptr %ir-sizep.addr.397)
  store ptr %t400, ptr %irs.addr.399, align 8
  %t401 = load ptr, ptr %irs.addr.399, align 8
  %t402 = getelementptr inbounds [30 x i8], ptr @.str.572, i64 0, i64 0
  %t403 = load ptr, ptr %macro-name.addr.30, align 8
  %t404 = call i32 (ptr, ptr, ...) @fprintf(ptr %t401, ptr %t402, ptr %t403)
  %t405 = load ptr, ptr %irs.addr.399, align 8
  %t406 = getelementptr inbounds [40 x i8], ptr @.str.573, i64 0, i64 0
  %t407 = call i32 (ptr, ptr, ...) @fprintf(ptr %t405, ptr %t406)
  %t408 = load ptr, ptr @g-type-bufp, align 8
  %t409 = icmp ne ptr %t408, null
  store i1 %t409, ptr %and.val23, align 1
  br i1 %t409, label %and.rhs23, label %and.end23
and.rhs23:
  %t410 = load ptr, ptr @g-type-bufp, align 8
  %t411 = sext i32 0 to i64
  %t412 = call i32 @char-at(ptr %t410, i64 %t411)
  %t413 = icmp ne i32 %t412, 0
  store i1 %t413, ptr %and.val23, align 1
  br label %and.end23
and.end23:
  %t414 = load i1, ptr %and.val23, align 1
  br i1 %t414, label %cond.then22.0, label %cond.end22
cond.then22.0:
  %t415 = load ptr, ptr @g-type-bufp, align 8
  %t416 = load ptr, ptr %irs.addr.399, align 8
  %t417 = call i32 @fputs(ptr %t415, ptr %t416)
  br label %cond.end22
cond.end22:
  %t418 = load ptr, ptr %irs.addr.399, align 8
  call void @emit-string-table(ptr %t418)
  %t419 = load ptr, ptr @g-decl-bufp, align 8
  %t420 = icmp ne ptr %t419, null
  store i1 %t420, ptr %and.val25, align 1
  br i1 %t420, label %and.rhs25, label %and.end25
and.rhs25:
  %t421 = load ptr, ptr @g-decl-bufp, align 8
  %t422 = sext i32 0 to i64
  %t423 = call i32 @char-at(ptr %t421, i64 %t422)
  %t424 = icmp ne i32 %t423, 0
  store i1 %t424, ptr %and.val25, align 1
  br label %and.end25
and.end25:
  %t425 = load i1, ptr %and.val25, align 1
  br i1 %t425, label %cond.then24.0, label %cond.end24
cond.then24.0:
  %t426 = load ptr, ptr @g-decl-bufp, align 8
  %t427 = load ptr, ptr %irs.addr.399, align 8
  %t428 = call i32 @fputs(ptr %t426, ptr %t427)
  br label %cond.end24
cond.end24:
  %t429 = load ptr, ptr %ct-decl-bufp.addr.142, align 8
  %t430 = icmp ne ptr %t429, null
  store i1 %t430, ptr %and.val27, align 1
  br i1 %t430, label %and.rhs27, label %and.end27
and.rhs27:
  %t431 = load ptr, ptr %ct-decl-bufp.addr.142, align 8
  %t432 = sext i32 0 to i64
  %t433 = call i32 @char-at(ptr %t431, i64 %t432)
  %t434 = icmp ne i32 %t433, 0
  store i1 %t434, ptr %and.val27, align 1
  br label %and.end27
and.end27:
  %t435 = load i1, ptr %and.val27, align 1
  br i1 %t435, label %cond.then26.0, label %cond.end26
cond.then26.0:
  %t436 = load ptr, ptr %ct-decl-bufp.addr.142, align 8
  %t437 = load ptr, ptr %irs.addr.399, align 8
  %t438 = call i32 @fputs(ptr %t436, ptr %t437)
  br label %cond.end26
cond.end26:
  %t439 = load ptr, ptr %ct-def-bufp.addr.145, align 8
  %t440 = icmp ne ptr %t439, null
  store i1 %t440, ptr %and.val29, align 1
  br i1 %t440, label %and.rhs29, label %and.end29
and.rhs29:
  %t441 = load ptr, ptr %ct-def-bufp.addr.145, align 8
  %t442 = sext i32 0 to i64
  %t443 = call i32 @char-at(ptr %t441, i64 %t442)
  %t444 = icmp ne i32 %t443, 0
  store i1 %t444, ptr %and.val29, align 1
  br label %and.end29
and.end29:
  %t445 = load i1, ptr %and.val29, align 1
  br i1 %t445, label %cond.then28.0, label %cond.end28
cond.then28.0:
  %t446 = load ptr, ptr %ct-def-bufp.addr.145, align 8
  %t447 = load ptr, ptr %irs.addr.399, align 8
  %t448 = call i32 @fputs(ptr %t446, ptr %t447)
  br label %cond.end28
cond.end28:
  %t449 = load ptr, ptr %irs.addr.399, align 8
  %t450 = call i32 @fclose(ptr %t449)
  %t451 = load ptr, ptr %ir-bufp.addr.396, align 8
  %t452 = load ptr, ptr %ff.addr.0, align 8
  %t453 = getelementptr inbounds %Node, ptr %t452, i32 0, i32 1
  %t454 = load i32, ptr %t453, align 4
  call void @jit-add-module(ptr %t451, i32 %t454)
  %t455 = load ptr, ptr %ct-decl-bufp.addr.142, align 8
  call void @free(ptr %t455)
  %t456 = load ptr, ptr %ct-def-bufp.addr.145, align 8
  call void @free(ptr %t456)
  %t457 = load ptr, ptr %ir-bufp.addr.396, align 8
  call void @free(ptr %t457)
  ret void
}

define void @emit-string-table(ptr %out.arg) {
entry:
  %out.addr = alloca ptr, align 8
  store ptr %out.arg, ptr %out.addr, align 8
  %i.addr.0 = alloca i32, align 4
  %sl.addr.4 = alloca ptr, align 8
  %ir-len.addr.9 = alloca i32, align 4
  %j.addr.21 = alloca i32, align 4
  %c.addr.27 = alloca i32, align 4
  %or.val3 = alloca i1, align 1
  %or.val4 = alloca i1, align 1
  %or.val5 = alloca i1, align 1
  store i32 0, ptr %i.addr.0, align 4
  br label %while.cond0
while.cond0:
  %t1 = load i32, ptr %i.addr.0, align 4
  %t2 = load i32, ptr @g-strs-len, align 4
  %t3 = icmp slt i32 %t1, %t2
  br i1 %t3, label %while.body0, label %while.end0
while.body0:
  %t5 = load ptr, ptr @g-strs, align 8
  %t6 = load i32, ptr %i.addr.0, align 4
  %t7 = sext i32 %t6 to i64
  %t8 = getelementptr inbounds %StrLit, ptr %t5, i64 %t7
  store ptr %t8, ptr %sl.addr.4, align 8
  %t10 = load ptr, ptr %sl.addr.4, align 8
  %t11 = getelementptr inbounds %StrLit, ptr %t10, i32 0, i32 1
  %t12 = load i32, ptr %t11, align 4
  %t13 = add nsw i32 %t12, 1
  store i32 %t13, ptr %ir-len.addr.9, align 4
  %t14 = load ptr, ptr %out.addr, align 8
  %t15 = getelementptr inbounds [54 x i8], ptr @.str.574, i64 0, i64 0
  %t16 = load ptr, ptr %sl.addr.4, align 8
  %t17 = getelementptr inbounds %StrLit, ptr %t16, i32 0, i32 2
  %t18 = load i32, ptr %t17, align 4
  %t19 = load i32, ptr %ir-len.addr.9, align 4
  %t20 = call i32 (ptr, ptr, ...) @fprintf(ptr %t14, ptr %t15, i32 %t18, i32 %t19)
  store i32 0, ptr %j.addr.21, align 4
  br label %while.cond1
while.cond1:
  %t22 = load i32, ptr %j.addr.21, align 4
  %t23 = load ptr, ptr %sl.addr.4, align 8
  %t24 = getelementptr inbounds %StrLit, ptr %t23, i32 0, i32 1
  %t25 = load i32, ptr %t24, align 4
  %t26 = icmp slt i32 %t22, %t25
  br i1 %t26, label %while.body1, label %while.end1
while.body1:
  %t28 = load ptr, ptr %sl.addr.4, align 8
  %t29 = getelementptr inbounds %StrLit, ptr %t28, i32 0, i32 0
  %t30 = load ptr, ptr %t29, align 8
  %t31 = load i32, ptr %j.addr.21, align 4
  %t32 = call i64 @i64(i32 %t31)
  %t33 = call i32 @char-at(ptr %t30, i64 %t32)
  store i32 %t33, ptr %c.addr.27, align 4
  %t34 = load i32, ptr %c.addr.27, align 4
  %t35 = icmp eq i32 %t34, 92
  store i1 %t35, ptr %or.val4, align 1
  br i1 %t35, label %or.end4, label %or.rhs4
or.rhs4:
  %t36 = load i32, ptr %c.addr.27, align 4
  %t37 = icmp eq i32 %t36, 34
  store i1 %t37, ptr %or.val4, align 1
  br label %or.end4
or.end4:
  %t38 = load i1, ptr %or.val4, align 1
  store i1 %t38, ptr %or.val3, align 1
  br i1 %t38, label %or.end3, label %or.rhs3
or.rhs3:
  %t39 = load i32, ptr %c.addr.27, align 4
  %t40 = icmp slt i32 %t39, 32
  store i1 %t40, ptr %or.val5, align 1
  br i1 %t40, label %or.end5, label %or.rhs5
or.rhs5:
  %t41 = load i32, ptr %c.addr.27, align 4
  %t42 = icmp sge i32 %t41, 127
  store i1 %t42, ptr %or.val5, align 1
  br label %or.end5
or.end5:
  %t43 = load i1, ptr %or.val5, align 1
  store i1 %t43, ptr %or.val3, align 1
  br label %or.end3
or.end3:
  %t44 = load i1, ptr %or.val3, align 1
  br i1 %t44, label %cond.then2.0, label %cond.test2.1
cond.then2.0:
  %t45 = load ptr, ptr %out.addr, align 8
  %t46 = getelementptr inbounds [6 x i8], ptr @.str.575, i64 0, i64 0
  %t47 = load i32, ptr %c.addr.27, align 4
  %t48 = call i32 (ptr, ptr, ...) @fprintf(ptr %t45, ptr %t46, i32 %t47)
  br label %cond.end2
cond.test2.1:
  br i1 1, label %cond.then2.1, label %cond.end2
cond.then2.1:
  %t49 = load i32, ptr %c.addr.27, align 4
  %t50 = load ptr, ptr %out.addr, align 8
  %t51 = call i32 @fputc(i32 %t49, ptr %t50)
  br label %cond.end2
cond.end2:
  %t52 = load i32, ptr %j.addr.21, align 4
  %t53 = add nsw i32 %t52, 1
  store i32 %t53, ptr %j.addr.21, align 4
  br label %while.cond1
while.end1:
  %t54 = load ptr, ptr %out.addr, align 8
  %t55 = getelementptr inbounds [15 x i8], ptr @.str.576, i64 0, i64 0
  %t56 = call i32 (ptr, ptr, ...) @fprintf(ptr %t54, ptr %t55)
  %t57 = load i32, ptr %i.addr.0, align 4
  %t58 = add nsw i32 %t57, 1
  store i32 %t58, ptr %i.addr.0, align 4
  br label %while.cond0
while.end0:
  %t59 = load i32, ptr @g-strs-len, align 4
  %t60 = icmp ne i32 %t59, 0
  br i1 %t60, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t61 = load ptr, ptr %out.addr, align 8
  %t62 = call i32 @fputc(i32 10, ptr %t61)
  br label %cond.end6
cond.end6:
  ret void
}

define ptr @read-file(ptr %path.arg) {
entry:
  %path.addr = alloca ptr, align 8
  store ptr %path.arg, ptr %path.addr, align 8
  %f.addr.0 = alloca ptr, align 8
  %sz.addr.12 = alloca i64, align 8
  %buf.addr.20 = alloca ptr, align 8
  %nr.addr.28 = alloca i64, align 8
  %t1 = load ptr, ptr %path.addr, align 8
  %t2 = getelementptr inbounds [3 x i8], ptr @.str.577, i64 0, i64 0
  %t3 = call ptr @fopen(ptr %t1, ptr %t2)
  store ptr %t3, ptr %f.addr.0, align 8
  %t4 = load ptr, ptr %f.addr.0, align 8
  %t5 = icmp eq ptr %t4, null
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t6 = load ptr, ptr %path.addr, align 8
  call void @perror(ptr %t6)
  call void @exit(i32 1)
  br label %cond.end0
cond.end0:
  %t7 = load ptr, ptr %f.addr.0, align 8
  %t8 = sext i32 0 to i64
  %t9 = call i32 @fseek(ptr %t7, i64 %t8, i32 2)
  %t10 = icmp ne i32 %t9, 0
  br i1 %t10, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t11 = getelementptr inbounds [6 x i8], ptr @.str.578, i64 0, i64 0
  call void @perror(ptr %t11)
  call void @exit(i32 1)
  br label %cond.end1
cond.end1:
  %t13 = load ptr, ptr %f.addr.0, align 8
  %t14 = call i64 @ftell(ptr %t13)
  store i64 %t14, ptr %sz.addr.12, align 8
  %t15 = load i64, ptr %sz.addr.12, align 8
  %t16 = sext i32 0 to i64
  %t17 = icmp slt i64 %t15, %t16
  br i1 %t17, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t18 = getelementptr inbounds [6 x i8], ptr @.str.579, i64 0, i64 0
  call void @perror(ptr %t18)
  call void @exit(i32 1)
  br label %cond.end2
cond.end2:
  %t19 = load ptr, ptr %f.addr.0, align 8
  call void @rewind(ptr %t19)
  %t21 = load i64, ptr %sz.addr.12, align 8
  %t22 = sext i32 1 to i64
  %t23 = add nsw i64 %t21, %t22
  %t24 = call ptr @malloc(i64 %t23)
  store ptr %t24, ptr %buf.addr.20, align 8
  %t25 = load ptr, ptr %buf.addr.20, align 8
  %t26 = icmp eq ptr %t25, null
  br i1 %t26, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t27 = getelementptr inbounds [7 x i8], ptr @.str.580, i64 0, i64 0
  call void @perror(ptr %t27)
  call void @exit(i32 1)
  br label %cond.end3
cond.end3:
  %t29 = load ptr, ptr %buf.addr.20, align 8
  %t30 = sext i32 1 to i64
  %t31 = load i64, ptr %sz.addr.12, align 8
  %t32 = load ptr, ptr %f.addr.0, align 8
  %t33 = call i64 @fread(ptr %t29, i64 %t30, i64 %t31, ptr %t32)
  store i64 %t33, ptr %nr.addr.28, align 8
  %t34 = load ptr, ptr %buf.addr.20, align 8
  %t35 = load i64, ptr %nr.addr.28, align 8
  %t36 = trunc i32 0 to i8
  %t37 = getelementptr inbounds i8, ptr %t34, i64 %t35
  store i8 %t36, ptr %t37, align 1
  %t38 = load ptr, ptr %f.addr.0, align 8
  %t39 = call i32 @fclose(ptr %t38)
  %t40 = load ptr, ptr %buf.addr.20, align 8
  ret ptr %t40
}

define i32 @main(i32 %argc.arg, ptr %argv.arg) {
entry:
  %argc.addr = alloca i32, align 4
  store i32 %argc.arg, ptr %argc.addr, align 4
  %argv.addr = alloca ptr, align 8
  store ptr %argv.arg, ptr %argv.addr, align 8
  %source-file.addr.5 = alloca ptr, align 8
  %src.addr.11 = alloca ptr, align 8
  %forms.addr.26 = alloca ptr, align 8
  %type-stream.addr.32 = alloca ptr, align 8
  %decl-stream.addr.34 = alloca ptr, align 8
  %def-stream.addr.36 = alloca ptr, align 8
  %fc.addr.39 = alloca ptr, align 8
  %f.addr.43 = alloca ptr, align 8
  %and.val3 = alloca i1, align 1
  %and.val4 = alloca i1, align 1
  %and.val5 = alloca i1, align 1
  %and.val6 = alloca i1, align 1
  %name-node.addr.72 = alloca ptr, align 8
  %params-node.addr.75 = alloca ptr, align 8
  %and.val8 = alloca i1, align 1
  %fname.addr.86 = alloca ptr, align 8
  %ret-name.addr.87 = alloca ptr, align 8
  %ret.addr.93 = alloca ptr, align 8
  %nparams.addr.99 = alloca i32, align 4
  %ptypes.addr.102 = alloca ptr, align 8
  %j.addr.110 = alloca i32, align 4
  %p.addr.114 = alloca ptr, align 8
  %pn.addr.122 = alloca ptr, align 8
  %pt-name.addr.123 = alloca ptr, align 8
  %ft.addr.145 = alloca ptr, align 8
  %fc.addr.166 = alloca ptr, align 8
  %f.addr.170 = alloca ptr, align 8
  %or.val16 = alloca i1, align 1
  %or.val17 = alloca i1, align 1
  %or.val18 = alloca i1, align 1
  %h.addr.195 = alloca ptr, align 8
  %and.val22 = alloca i1, align 1
  %and.val24 = alloca i1, align 1
  %and.val26 = alloca i1, align 1
  %t0 = load i32, ptr %argc.addr, align 4
  %t1 = icmp ne i32 %t0, 2
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t2 = load ptr, ptr @stderr, align 8
  %t3 = getelementptr inbounds [28 x i8], ptr @.str.581, i64 0, i64 0
  %t4 = call i32 (ptr, ptr, ...) @fprintf(ptr %t2, ptr %t3)
  ret i32 2
cond.end0:
  %t6 = load ptr, ptr %argv.addr, align 8
  %t7 = sext i32 1 to i64
  %t8 = getelementptr inbounds ptr, ptr %t6, i64 %t7
  %t9 = load ptr, ptr %t8, align 8
  store ptr %t9, ptr %source-file.addr.5, align 8
  %t10 = load ptr, ptr %source-file.addr.5, align 8
  store ptr %t10, ptr @g-source-path, align 8
  %t12 = load ptr, ptr %source-file.addr.5, align 8
  %t13 = call ptr @read-file(ptr %t12)
  store ptr %t13, ptr %src.addr.11, align 8
  call void @arena-init()
  call void @types-init()
  call void @init-binops()
  call void @init-libc()
  %t14 = sext i32 64 to i64
  %t15 = getelementptr %StructDef, ptr null, i32 1
  %t16 = ptrtoint ptr %t15 to i64
  %t17 = mul nsw i64 %t14, %t16
  %t18 = call ptr @arena-alloc(i64 %t17)
  store ptr %t18, ptr @g-structs, align 8
  %t19 = sext i32 256 to i64
  %t20 = getelementptr %MacroDef, ptr null, i32 1
  %t21 = ptrtoint ptr %t20 to i64
  %t22 = mul nsw i64 %t19, %t21
  %t23 = call ptr @arena-alloc(i64 %t22)
  store ptr %t23, ptr @g-macros, align 8
  %t24 = load ptr, ptr %src.addr.11, align 8
  store ptr %t24, ptr @g-src, align 8
  %t25 = sext i32 0 to i64
  store i64 %t25, ptr @g-pos, align 8
  store i32 1, ptr @g-line, align 4
  %t27 = call ptr @read-program()
  store ptr %t27, ptr %forms.addr.26, align 8
  %t28 = call ptr @scope-new(ptr null)
  store ptr %t28, ptr @g-globals, align 8
  %t29 = call ptr @open_memstream(ptr @g-type-bufp, ptr @g-type-sizep)
  store ptr %t29, ptr @g-type-stream, align 8
  %t30 = call ptr @open_memstream(ptr @g-decl-bufp, ptr @g-decl-sizep)
  store ptr %t30, ptr @g-decl-stream, align 8
  %t31 = call ptr @open_memstream(ptr @g-def-bufp, ptr @g-def-sizep)
  store ptr %t31, ptr @g-def-stream, align 8
  %t33 = load ptr, ptr @g-type-stream, align 8
  store ptr %t33, ptr %type-stream.addr.32, align 8
  %t35 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t35, ptr %decl-stream.addr.34, align 8
  %t37 = load ptr, ptr @g-def-stream, align 8
  store ptr %t37, ptr %def-stream.addr.36, align 8
  %t38 = load ptr, ptr %decl-stream.addr.34, align 8
  store ptr %t38, ptr @g-decl-out, align 8
  %t40 = load ptr, ptr %forms.addr.26, align 8
  store ptr %t40, ptr %fc.addr.39, align 8
  br label %while.cond1
while.cond1:
  %t41 = load ptr, ptr %fc.addr.39, align 8
  %t42 = icmp ne ptr %t41, null
  br i1 %t42, label %while.body1, label %while.end1
while.body1:
  %t44 = load ptr, ptr %fc.addr.39, align 8
  %t45 = getelementptr inbounds %Node, ptr %t44, i32 0, i32 4
  %t46 = load ptr, ptr %t45, align 8
  store ptr %t46, ptr %f.addr.43, align 8
  %t47 = load ptr, ptr %f.addr.43, align 8
  %t48 = icmp ne ptr %t47, null
  store i1 %t48, ptr %and.val4, align 1
  br i1 %t48, label %and.rhs4, label %and.end4
and.rhs4:
  %t49 = load ptr, ptr %f.addr.43, align 8
  %t50 = getelementptr inbounds %Node, ptr %t49, i32 0, i32 0
  %t51 = load i32, ptr %t50, align 4
  %t52 = icmp eq i32 %t51, 3
  store i1 %t52, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t53 = load i1, ptr %and.val4, align 1
  store i1 %t53, ptr %and.val3, align 1
  br i1 %t53, label %and.rhs3, label %and.end3
and.rhs3:
  %t54 = load ptr, ptr %f.addr.43, align 8
  %t55 = call i32 @node-len(ptr %t54)
  %t56 = icmp sge i32 %t55, 4
  store i1 %t56, ptr %and.val5, align 1
  br i1 %t56, label %and.rhs5, label %and.end5
and.rhs5:
  %t57 = load ptr, ptr %f.addr.43, align 8
  %t58 = call ptr @node-at(ptr %t57, i32 0)
  %t59 = getelementptr inbounds %Node, ptr %t58, i32 0, i32 0
  %t60 = load i32, ptr %t59, align 4
  %t61 = icmp eq i32 %t60, 2
  store i1 %t61, ptr %and.val6, align 1
  br i1 %t61, label %and.rhs6, label %and.end6
and.rhs6:
  %t62 = load ptr, ptr %f.addr.43, align 8
  %t63 = call ptr @node-at(ptr %t62, i32 0)
  %t64 = getelementptr inbounds %Node, ptr %t63, i32 0, i32 3
  %t65 = load ptr, ptr %t64, align 8
  %t66 = getelementptr inbounds [5 x i8], ptr @.str.582, i64 0, i64 0
  %t67 = call i32 @strcmp(ptr %t65, ptr %t66)
  %t68 = icmp eq i32 %t67, 0
  store i1 %t68, ptr %and.val6, align 1
  br label %and.end6
and.end6:
  %t69 = load i1, ptr %and.val6, align 1
  store i1 %t69, ptr %and.val5, align 1
  br label %and.end5
and.end5:
  %t70 = load i1, ptr %and.val5, align 1
  store i1 %t70, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t71 = load i1, ptr %and.val3, align 1
  br i1 %t71, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t73 = load ptr, ptr %f.addr.43, align 8
  %t74 = call ptr @node-at(ptr %t73, i32 1)
  store ptr %t74, ptr %name-node.addr.72, align 8
  %t76 = load ptr, ptr %f.addr.43, align 8
  %t77 = call ptr @node-at(ptr %t76, i32 2)
  store ptr %t77, ptr %params-node.addr.75, align 8
  %t78 = load ptr, ptr %name-node.addr.72, align 8
  %t79 = getelementptr inbounds %Node, ptr %t78, i32 0, i32 0
  %t80 = load i32, ptr %t79, align 4
  %t81 = icmp eq i32 %t80, 2
  store i1 %t81, ptr %and.val8, align 1
  br i1 %t81, label %and.rhs8, label %and.end8
and.rhs8:
  %t82 = load ptr, ptr %params-node.addr.75, align 8
  %t83 = call i32 @node-is-list(ptr %t82)
  %t84 = icmp ne i32 %t83, 0
  store i1 %t84, ptr %and.val8, align 1
  br label %and.end8
and.end8:
  %t85 = load i1, ptr %and.val8, align 1
  br i1 %t85, label %cond.then7.0, label %cond.end7
cond.then7.0:
  store ptr null, ptr %fname.addr.86, align 8
  store ptr null, ptr %ret-name.addr.87, align 8
  %t88 = load ptr, ptr %name-node.addr.72, align 8
  %t89 = getelementptr inbounds %Node, ptr %t88, i32 0, i32 3
  %t90 = load ptr, ptr %t89, align 8
  call void @split-typed(ptr %t90, ptr %fname.addr.86, ptr %ret-name.addr.87)
  %t91 = load ptr, ptr %ret-name.addr.87, align 8
  %t92 = icmp ne ptr %t91, null
  br i1 %t92, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t94 = load ptr, ptr %ret-name.addr.87, align 8
  %t95 = load ptr, ptr %name-node.addr.72, align 8
  %t96 = getelementptr inbounds %Node, ptr %t95, i32 0, i32 1
  %t97 = load i32, ptr %t96, align 4
  %t98 = call ptr @parse-type-name(ptr %t94, i32 %t97)
  store ptr %t98, ptr %ret.addr.93, align 8
  %t100 = load ptr, ptr %params-node.addr.75, align 8
  %t101 = call i32 @node-len(ptr %t100)
  store i32 %t101, ptr %nparams.addr.99, align 4
  store ptr null, ptr %ptypes.addr.102, align 8
  %t103 = load i32, ptr %nparams.addr.99, align 4
  %t104 = icmp sgt i32 %t103, 0
  br i1 %t104, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t105 = load i32, ptr %nparams.addr.99, align 4
  %t106 = call i64 @i64(i32 %t105)
  %t107 = call i64 @i64(i32 8)
  %t108 = mul nsw i64 %t106, %t107
  %t109 = call ptr @arena-alloc(i64 %t108)
  store ptr %t109, ptr %ptypes.addr.102, align 8
  br label %cond.end10
cond.end10:
  store i32 0, ptr %j.addr.110, align 4
  br label %while.cond11
while.cond11:
  %t111 = load i32, ptr %j.addr.110, align 4
  %t112 = load i32, ptr %nparams.addr.99, align 4
  %t113 = icmp slt i32 %t111, %t112
  br i1 %t113, label %while.body11, label %while.end11
while.body11:
  %t115 = load ptr, ptr %params-node.addr.75, align 8
  %t116 = load i32, ptr %j.addr.110, align 4
  %t117 = call ptr @node-at(ptr %t115, i32 %t116)
  store ptr %t117, ptr %p.addr.114, align 8
  %t118 = load ptr, ptr %p.addr.114, align 8
  %t119 = getelementptr inbounds %Node, ptr %t118, i32 0, i32 0
  %t120 = load i32, ptr %t119, align 4
  %t121 = icmp eq i32 %t120, 2
  br i1 %t121, label %cond.then12.0, label %cond.end12
cond.then12.0:
  store ptr null, ptr %pn.addr.122, align 8
  store ptr null, ptr %pt-name.addr.123, align 8
  %t124 = load ptr, ptr %p.addr.114, align 8
  %t125 = getelementptr inbounds %Node, ptr %t124, i32 0, i32 3
  %t126 = load ptr, ptr %t125, align 8
  call void @split-typed(ptr %t126, ptr %pn.addr.122, ptr %pt-name.addr.123)
  %t127 = load ptr, ptr %pt-name.addr.123, align 8
  %t128 = icmp ne ptr %t127, null
  br i1 %t128, label %cond.then13.0, label %cond.test13.1
cond.then13.0:
  %t129 = load ptr, ptr %ptypes.addr.102, align 8
  %t130 = load i32, ptr %j.addr.110, align 4
  %t131 = sext i32 %t130 to i64
  %t132 = load ptr, ptr %pt-name.addr.123, align 8
  %t133 = load ptr, ptr %p.addr.114, align 8
  %t134 = getelementptr inbounds %Node, ptr %t133, i32 0, i32 1
  %t135 = load i32, ptr %t134, align 4
  %t136 = call ptr @parse-type-name(ptr %t132, i32 %t135)
  %t137 = getelementptr inbounds ptr, ptr %t129, i64 %t131
  store ptr %t136, ptr %t137, align 8
  br label %cond.end13
cond.test13.1:
  br i1 1, label %cond.then13.1, label %cond.end13
cond.then13.1:
  %t138 = load ptr, ptr %ptypes.addr.102, align 8
  %t139 = load i32, ptr %j.addr.110, align 4
  %t140 = sext i32 %t139 to i64
  %t141 = load ptr, ptr @ty-i32, align 8
  %t142 = getelementptr inbounds ptr, ptr %t138, i64 %t140
  store ptr %t141, ptr %t142, align 8
  br label %cond.end13
cond.end13:
  br label %cond.end12
cond.end12:
  %t143 = load i32, ptr %j.addr.110, align 4
  %t144 = add nsw i32 %t143, 1
  store i32 %t144, ptr %j.addr.110, align 4
  br label %while.cond11
while.end11:
  %t146 = call ptr @make-type(i32 7)
  store ptr %t146, ptr %ft.addr.145, align 8
  %t147 = load ptr, ptr %ft.addr.145, align 8
  %t148 = load ptr, ptr %ret.addr.93, align 8
  %t149 = getelementptr inbounds %Type, ptr %t147, i32 0, i32 1
  store ptr %t148, ptr %t149, align 8
  %t150 = load ptr, ptr %ft.addr.145, align 8
  %t151 = load i32, ptr %nparams.addr.99, align 4
  %t152 = getelementptr inbounds %Type, ptr %t150, i32 0, i32 3
  store i32 %t151, ptr %t152, align 4
  %t153 = load ptr, ptr %ft.addr.145, align 8
  %t154 = load ptr, ptr %ptypes.addr.102, align 8
  %t155 = getelementptr inbounds %Type, ptr %t153, i32 0, i32 2
  store ptr %t154, ptr %t155, align 8
  %t156 = load ptr, ptr @g-globals, align 8
  %t157 = load ptr, ptr %fname.addr.86, align 8
  %t158 = load ptr, ptr %ft.addr.145, align 8
  %t159 = getelementptr inbounds [4 x i8], ptr @.str.583, i64 0, i64 0
  %t160 = load ptr, ptr %fname.addr.86, align 8
  %t161 = call ptr @fmt-s(ptr %t159, ptr %t160)
  %t162 = call ptr @scope-define(ptr %t156, ptr %t157, ptr %t158, ptr %t161, i32 0)
  br label %cond.end9
cond.end9:
  br label %cond.end7
cond.end7:
  br label %cond.end2
cond.end2:
  %t163 = load ptr, ptr %fc.addr.39, align 8
  %t164 = getelementptr inbounds %Node, ptr %t163, i32 0, i32 5
  %t165 = load ptr, ptr %t164, align 8
  store ptr %t165, ptr %fc.addr.39, align 8
  br label %while.cond1
while.end1:
  %t167 = load ptr, ptr %forms.addr.26, align 8
  store ptr %t167, ptr %fc.addr.166, align 8
  br label %while.cond14
while.cond14:
  %t168 = load ptr, ptr %fc.addr.166, align 8
  %t169 = icmp ne ptr %t168, null
  br i1 %t169, label %while.body14, label %while.end14
while.body14:
  %t171 = load ptr, ptr %fc.addr.166, align 8
  %t172 = getelementptr inbounds %Node, ptr %t171, i32 0, i32 4
  %t173 = load ptr, ptr %t172, align 8
  store ptr %t173, ptr %f.addr.170, align 8
  %t174 = load ptr, ptr %f.addr.170, align 8
  %t175 = icmp eq ptr %t174, null
  store i1 %t175, ptr %or.val17, align 1
  br i1 %t175, label %or.end17, label %or.rhs17
or.rhs17:
  %t176 = load ptr, ptr %f.addr.170, align 8
  %t177 = getelementptr inbounds %Node, ptr %t176, i32 0, i32 0
  %t178 = load i32, ptr %t177, align 4
  %t179 = icmp ne i32 %t178, 3
  store i1 %t179, ptr %or.val17, align 1
  br label %or.end17
or.end17:
  %t180 = load i1, ptr %or.val17, align 1
  store i1 %t180, ptr %or.val16, align 1
  br i1 %t180, label %or.end16, label %or.rhs16
or.rhs16:
  %t181 = load ptr, ptr %f.addr.170, align 8
  %t182 = call i32 @node-len(ptr %t181)
  %t183 = icmp eq i32 %t182, 0
  store i1 %t183, ptr %or.val18, align 1
  br i1 %t183, label %or.end18, label %or.rhs18
or.rhs18:
  %t184 = load ptr, ptr %f.addr.170, align 8
  %t185 = call ptr @node-at(ptr %t184, i32 0)
  %t186 = getelementptr inbounds %Node, ptr %t185, i32 0, i32 0
  %t187 = load i32, ptr %t186, align 4
  %t188 = icmp ne i32 %t187, 2
  store i1 %t188, ptr %or.val18, align 1
  br label %or.end18
or.end18:
  %t189 = load i1, ptr %or.val18, align 1
  store i1 %t189, ptr %or.val16, align 1
  br label %or.end16
or.end16:
  %t190 = load i1, ptr %or.val16, align 1
  br i1 %t190, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t191 = load ptr, ptr %f.addr.170, align 8
  %t192 = getelementptr inbounds %Node, ptr %t191, i32 0, i32 1
  %t193 = load i32, ptr %t192, align 4
  %t194 = getelementptr inbounds [53 x i8], ptr @.str.584, i64 0, i64 0
  call void @die-at(i32 %t193, ptr %t194)
  br label %cond.end15
cond.end15:
  %t196 = load ptr, ptr %f.addr.170, align 8
  %t197 = call ptr @node-at(ptr %t196, i32 0)
  %t198 = getelementptr inbounds %Node, ptr %t197, i32 0, i32 3
  %t199 = load ptr, ptr %t198, align 8
  store ptr %t199, ptr %h.addr.195, align 8
  %t200 = load ptr, ptr %h.addr.195, align 8
  %t201 = getelementptr inbounds [9 x i8], ptr @.str.585, i64 0, i64 0
  %t202 = call i32 @strcmp(ptr %t200, ptr %t201)
  %t203 = icmp eq i32 %t202, 0
  br i1 %t203, label %cond.then19.0, label %cond.test19.1
cond.then19.0:
  %t204 = load ptr, ptr %f.addr.170, align 8
  call void @emit-defconst(ptr %t204)
  br label %cond.end19
cond.test19.1:
  %t205 = load ptr, ptr %h.addr.195, align 8
  %t206 = getelementptr inbounds [8 x i8], ptr @.str.586, i64 0, i64 0
  %t207 = call i32 @strcmp(ptr %t205, ptr %t206)
  %t208 = icmp eq i32 %t207, 0
  br i1 %t208, label %cond.then19.1, label %cond.test19.2
cond.then19.1:
  %t209 = load ptr, ptr %f.addr.170, align 8
  call void @emit-defenum(ptr %t209)
  br label %cond.end19
cond.test19.2:
  %t210 = load ptr, ptr %h.addr.195, align 8
  %t211 = getelementptr inbounds [7 x i8], ptr @.str.587, i64 0, i64 0
  %t212 = call i32 @strcmp(ptr %t210, ptr %t211)
  %t213 = icmp eq i32 %t212, 0
  br i1 %t213, label %cond.then19.2, label %cond.test19.3
cond.then19.2:
  %t214 = load ptr, ptr %decl-stream.addr.34, align 8
  store ptr %t214, ptr @g-out, align 8
  %t215 = load ptr, ptr %f.addr.170, align 8
  call void @emit-defvar(ptr %t215)
  br label %cond.end19
cond.test19.3:
  %t216 = load ptr, ptr %h.addr.195, align 8
  %t217 = getelementptr inbounds [10 x i8], ptr @.str.588, i64 0, i64 0
  %t218 = call i32 @strcmp(ptr %t216, ptr %t217)
  %t219 = icmp eq i32 %t218, 0
  br i1 %t219, label %cond.then19.3, label %cond.test19.4
cond.then19.3:
  %t220 = load ptr, ptr %type-stream.addr.32, align 8
  store ptr %t220, ptr @g-out, align 8
  %t221 = load ptr, ptr %f.addr.170, align 8
  call void @emit-defstruct(ptr %t221)
  br label %cond.end19
cond.test19.4:
  %t222 = load ptr, ptr %h.addr.195, align 8
  %t223 = getelementptr inbounds [8 x i8], ptr @.str.589, i64 0, i64 0
  %t224 = call i32 @strcmp(ptr %t222, ptr %t223)
  %t225 = icmp eq i32 %t224, 0
  br i1 %t225, label %cond.then19.4, label %cond.test19.5
cond.then19.4:
  %t226 = load ptr, ptr %decl-stream.addr.34, align 8
  store ptr %t226, ptr @g-out, align 8
  %t227 = load ptr, ptr %f.addr.170, align 8
  call void @emit-include(ptr %t227)
  br label %cond.end19
cond.test19.5:
  %t228 = load ptr, ptr %h.addr.195, align 8
  %t229 = getelementptr inbounds [7 x i8], ptr @.str.590, i64 0, i64 0
  %t230 = call i32 @strcmp(ptr %t228, ptr %t229)
  %t231 = icmp eq i32 %t230, 0
  br i1 %t231, label %cond.then19.5, label %cond.test19.6
cond.then19.5:
  %t232 = load ptr, ptr %decl-stream.addr.34, align 8
  store ptr %t232, ptr @g-out, align 8
  %t233 = load ptr, ptr %f.addr.170, align 8
  call void @emit-extern(ptr %t233)
  br label %cond.end19
cond.test19.6:
  %t234 = load ptr, ptr %h.addr.195, align 8
  %t235 = getelementptr inbounds [5 x i8], ptr @.str.591, i64 0, i64 0
  %t236 = call i32 @strcmp(ptr %t234, ptr %t235)
  %t237 = icmp eq i32 %t236, 0
  br i1 %t237, label %cond.then19.6, label %cond.test19.7
cond.then19.6:
  %t238 = load ptr, ptr %def-stream.addr.36, align 8
  store ptr %t238, ptr @g-out, align 8
  %t239 = load ptr, ptr %f.addr.170, align 8
  call void @emit-defn(ptr %t239)
  br label %cond.end19
cond.test19.7:
  %t240 = load ptr, ptr %h.addr.195, align 8
  %t241 = getelementptr inbounds [13 x i8], ptr @.str.592, i64 0, i64 0
  %t242 = call i32 @strcmp(ptr %t240, ptr %t241)
  %t243 = icmp eq i32 %t242, 0
  br i1 %t243, label %cond.then19.7, label %cond.test19.8
cond.then19.7:
  %t244 = load ptr, ptr %f.addr.170, align 8
  call void @emit-compile-time(ptr %t244)
  br label %cond.end19
cond.test19.8:
  %t245 = load ptr, ptr %h.addr.195, align 8
  %t246 = getelementptr inbounds [9 x i8], ptr @.str.593, i64 0, i64 0
  %t247 = call i32 @strcmp(ptr %t245, ptr %t246)
  %t248 = icmp eq i32 %t247, 0
  br i1 %t248, label %cond.then19.8, label %cond.test19.9
cond.then19.8:
  %t249 = load ptr, ptr %f.addr.170, align 8
  call void @emit-defmacro(ptr %t249)
  br label %cond.end19
cond.test19.9:
  br i1 1, label %cond.then19.9, label %cond.end19
cond.then19.9:
  %t250 = load ptr, ptr %f.addr.170, align 8
  %t251 = getelementptr inbounds %Node, ptr %t250, i32 0, i32 1
  %t252 = load i32, ptr %t251, align 4
  %t253 = getelementptr inbounds [27 x i8], ptr @.str.594, i64 0, i64 0
  %t254 = load ptr, ptr %h.addr.195, align 8
  %t255 = call ptr @fmt-s(ptr %t253, ptr %t254)
  call void @die-at(i32 %t252, ptr %t255)
  br label %cond.end19
cond.end19:
  %t256 = load ptr, ptr %fc.addr.166, align 8
  %t257 = getelementptr inbounds %Node, ptr %t256, i32 0, i32 5
  %t258 = load ptr, ptr %t257, align 8
  store ptr %t258, ptr %fc.addr.166, align 8
  br label %while.cond14
while.end14:
  %t259 = load i32, ptr @g-qq-used, align 4
  %t260 = icmp ne i32 %t259, 0
  br i1 %t260, label %cond.then20.0, label %cond.end20
cond.then20.0:
  %t261 = load ptr, ptr %decl-stream.addr.34, align 8
  %t262 = getelementptr inbounds [26 x i8], ptr @.str.595, i64 0, i64 0
  %t263 = call i32 (ptr, ptr, ...) @fprintf(ptr %t261, ptr %t262)
  %t264 = load ptr, ptr %def-stream.addr.36, align 8
  %t265 = getelementptr inbounds [40 x i8], ptr @.str.596, i64 0, i64 0
  %t266 = call i32 (ptr, ptr, ...) @fprintf(ptr %t264, ptr %t265)
  %t267 = load ptr, ptr %def-stream.addr.36, align 8
  %t268 = getelementptr inbounds [34 x i8], ptr @.str.597, i64 0, i64 0
  %t269 = call i32 (ptr, ptr, ...) @fprintf(ptr %t267, ptr %t268)
  %t270 = load ptr, ptr %def-stream.addr.36, align 8
  %t271 = getelementptr inbounds [89 x i8], ptr @.str.598, i64 0, i64 0
  %t272 = call i32 (ptr, ptr, ...) @fprintf(ptr %t270, ptr %t271)
  %t273 = load ptr, ptr %def-stream.addr.36, align 8
  %t274 = getelementptr inbounds [34 x i8], ptr @.str.599, i64 0, i64 0
  %t275 = call i32 (ptr, ptr, ...) @fprintf(ptr %t273, ptr %t274)
  %t276 = load ptr, ptr %def-stream.addr.36, align 8
  %t277 = getelementptr inbounds [89 x i8], ptr @.str.600, i64 0, i64 0
  %t278 = call i32 (ptr, ptr, ...) @fprintf(ptr %t276, ptr %t277)
  %t279 = load ptr, ptr %def-stream.addr.36, align 8
  %t280 = getelementptr inbounds [34 x i8], ptr @.str.601, i64 0, i64 0
  %t281 = call i32 (ptr, ptr, ...) @fprintf(ptr %t279, ptr %t280)
  %t282 = load ptr, ptr %def-stream.addr.36, align 8
  %t283 = getelementptr inbounds [89 x i8], ptr @.str.602, i64 0, i64 0
  %t284 = call i32 (ptr, ptr, ...) @fprintf(ptr %t282, ptr %t283)
  %t285 = load ptr, ptr %def-stream.addr.36, align 8
  %t286 = getelementptr inbounds [34 x i8], ptr @.str.603, i64 0, i64 0
  %t287 = call i32 (ptr, ptr, ...) @fprintf(ptr %t285, ptr %t286)
  %t288 = load ptr, ptr %def-stream.addr.36, align 8
  %t289 = getelementptr inbounds [89 x i8], ptr @.str.604, i64 0, i64 0
  %t290 = call i32 (ptr, ptr, ...) @fprintf(ptr %t288, ptr %t289)
  %t291 = load ptr, ptr %def-stream.addr.36, align 8
  %t292 = getelementptr inbounds [37 x i8], ptr @.str.605, i64 0, i64 0
  %t293 = call i32 (ptr, ptr, ...) @fprintf(ptr %t291, ptr %t292)
  %t294 = load ptr, ptr %def-stream.addr.36, align 8
  %t295 = getelementptr inbounds [89 x i8], ptr @.str.606, i64 0, i64 0
  %t296 = call i32 (ptr, ptr, ...) @fprintf(ptr %t294, ptr %t295)
  %t297 = load ptr, ptr %def-stream.addr.36, align 8
  %t298 = getelementptr inbounds [36 x i8], ptr @.str.607, i64 0, i64 0
  %t299 = call i32 (ptr, ptr, ...) @fprintf(ptr %t297, ptr %t298)
  %t300 = load ptr, ptr %def-stream.addr.36, align 8
  %t301 = getelementptr inbounds [89 x i8], ptr @.str.608, i64 0, i64 0
  %t302 = call i32 (ptr, ptr, ...) @fprintf(ptr %t300, ptr %t301)
  %t303 = load ptr, ptr %def-stream.addr.36, align 8
  %t304 = getelementptr inbounds [36 x i8], ptr @.str.609, i64 0, i64 0
  %t305 = call i32 (ptr, ptr, ...) @fprintf(ptr %t303, ptr %t304)
  %t306 = load ptr, ptr %def-stream.addr.36, align 8
  %t307 = getelementptr inbounds [15 x i8], ptr @.str.610, i64 0, i64 0
  %t308 = call i32 (ptr, ptr, ...) @fprintf(ptr %t306, ptr %t307)
  %t309 = load ptr, ptr %def-stream.addr.36, align 8
  %t310 = getelementptr inbounds [4 x i8], ptr @.str.611, i64 0, i64 0
  %t311 = call i32 (ptr, ptr, ...) @fprintf(ptr %t309, ptr %t310)
  %t312 = load ptr, ptr %def-stream.addr.36, align 8
  %t313 = getelementptr inbounds [42 x i8], ptr @.str.612, i64 0, i64 0
  %t314 = call i32 (ptr, ptr, ...) @fprintf(ptr %t312, ptr %t313)
  %t315 = load ptr, ptr %def-stream.addr.36, align 8
  %t316 = getelementptr inbounds [8 x i8], ptr @.str.613, i64 0, i64 0
  %t317 = call i32 (ptr, ptr, ...) @fprintf(ptr %t315, ptr %t316)
  %t318 = load ptr, ptr %def-stream.addr.36, align 8
  %t319 = getelementptr inbounds [31 x i8], ptr @.str.614, i64 0, i64 0
  %t320 = call i32 (ptr, ptr, ...) @fprintf(ptr %t318, ptr %t319)
  %t321 = load ptr, ptr %def-stream.addr.36, align 8
  %t322 = getelementptr inbounds [39 x i8], ptr @.str.615, i64 0, i64 0
  %t323 = call i32 (ptr, ptr, ...) @fprintf(ptr %t321, ptr %t322)
  %t324 = load ptr, ptr %def-stream.addr.36, align 8
  %t325 = getelementptr inbounds [6 x i8], ptr @.str.616, i64 0, i64 0
  %t326 = call i32 (ptr, ptr, ...) @fprintf(ptr %t324, ptr %t325)
  %t327 = load ptr, ptr %def-stream.addr.36, align 8
  %t328 = getelementptr inbounds [15 x i8], ptr @.str.617, i64 0, i64 0
  %t329 = call i32 (ptr, ptr, ...) @fprintf(ptr %t327, ptr %t328)
  %t330 = load ptr, ptr %def-stream.addr.36, align 8
  %t331 = getelementptr inbounds [6 x i8], ptr @.str.618, i64 0, i64 0
  %t332 = call i32 (ptr, ptr, ...) @fprintf(ptr %t330, ptr %t331)
  %t333 = load ptr, ptr %def-stream.addr.36, align 8
  %t334 = getelementptr inbounds [89 x i8], ptr @.str.619, i64 0, i64 0
  %t335 = call i32 (ptr, ptr, ...) @fprintf(ptr %t333, ptr %t334)
  %t336 = load ptr, ptr %def-stream.addr.36, align 8
  %t337 = getelementptr inbounds [39 x i8], ptr @.str.620, i64 0, i64 0
  %t338 = call i32 (ptr, ptr, ...) @fprintf(ptr %t336, ptr %t337)
  %t339 = load ptr, ptr %def-stream.addr.36, align 8
  %t340 = getelementptr inbounds [89 x i8], ptr @.str.621, i64 0, i64 0
  %t341 = call i32 (ptr, ptr, ...) @fprintf(ptr %t339, ptr %t340)
  %t342 = load ptr, ptr %def-stream.addr.36, align 8
  %t343 = getelementptr inbounds [39 x i8], ptr @.str.622, i64 0, i64 0
  %t344 = call i32 (ptr, ptr, ...) @fprintf(ptr %t342, ptr %t343)
  %t345 = load ptr, ptr %def-stream.addr.36, align 8
  %t346 = getelementptr inbounds [51 x i8], ptr @.str.623, i64 0, i64 0
  %t347 = call i32 (ptr, ptr, ...) @fprintf(ptr %t345, ptr %t346)
  %t348 = load ptr, ptr %def-stream.addr.36, align 8
  %t349 = getelementptr inbounds [49 x i8], ptr @.str.624, i64 0, i64 0
  %t350 = call i32 (ptr, ptr, ...) @fprintf(ptr %t348, ptr %t349)
  %t351 = load ptr, ptr %def-stream.addr.36, align 8
  %t352 = getelementptr inbounds [15 x i8], ptr @.str.625, i64 0, i64 0
  %t353 = call i32 (ptr, ptr, ...) @fprintf(ptr %t351, ptr %t352)
  %t354 = load ptr, ptr %def-stream.addr.36, align 8
  %t355 = getelementptr inbounds [4 x i8], ptr @.str.626, i64 0, i64 0
  %t356 = call i32 (ptr, ptr, ...) @fprintf(ptr %t354, ptr %t355)
  br label %cond.end20
cond.end20:
  %t357 = load ptr, ptr %type-stream.addr.32, align 8
  %t358 = call i32 @fclose(ptr %t357)
  %t359 = load ptr, ptr %decl-stream.addr.34, align 8
  %t360 = call i32 @fclose(ptr %t359)
  %t361 = load ptr, ptr %def-stream.addr.36, align 8
  %t362 = call i32 @fclose(ptr %t361)
  %t363 = getelementptr inbounds [19 x i8], ptr @.str.627, i64 0, i64 0
  %t364 = load ptr, ptr %source-file.addr.5, align 8
  %t365 = call i32 (ptr, ...) @printf(ptr %t363, ptr %t364)
  %t366 = getelementptr inbounds [24 x i8], ptr @.str.628, i64 0, i64 0
  %t367 = load ptr, ptr %source-file.addr.5, align 8
  %t368 = call i32 (ptr, ...) @printf(ptr %t366, ptr %t367)
  %t369 = getelementptr inbounds [40 x i8], ptr @.str.629, i64 0, i64 0
  %t370 = call i32 (ptr, ...) @printf(ptr %t369)
  %t371 = load ptr, ptr @g-type-bufp, align 8
  %t372 = icmp ne ptr %t371, null
  store i1 %t372, ptr %and.val22, align 1
  br i1 %t372, label %and.rhs22, label %and.end22
and.rhs22:
  %t373 = load ptr, ptr @g-type-bufp, align 8
  %t374 = sext i32 0 to i64
  %t375 = call i32 @char-at(ptr %t373, i64 %t374)
  %t376 = icmp ne i32 %t375, 0
  store i1 %t376, ptr %and.val22, align 1
  br label %and.end22
and.end22:
  %t377 = load i1, ptr %and.val22, align 1
  br i1 %t377, label %cond.then21.0, label %cond.end21
cond.then21.0:
  %t378 = load ptr, ptr @g-type-bufp, align 8
  %t379 = load ptr, ptr @stdout, align 8
  %t380 = call i32 @fputs(ptr %t378, ptr %t379)
  br label %cond.end21
cond.end21:
  %t381 = load ptr, ptr @stdout, align 8
  call void @emit-string-table(ptr %t381)
  %t382 = load ptr, ptr @g-decl-bufp, align 8
  %t383 = icmp ne ptr %t382, null
  store i1 %t383, ptr %and.val24, align 1
  br i1 %t383, label %and.rhs24, label %and.end24
and.rhs24:
  %t384 = load ptr, ptr @g-decl-bufp, align 8
  %t385 = sext i32 0 to i64
  %t386 = call i32 @char-at(ptr %t384, i64 %t385)
  %t387 = icmp ne i32 %t386, 0
  store i1 %t387, ptr %and.val24, align 1
  br label %and.end24
and.end24:
  %t388 = load i1, ptr %and.val24, align 1
  br i1 %t388, label %cond.then23.0, label %cond.end23
cond.then23.0:
  %t389 = load ptr, ptr @g-decl-bufp, align 8
  %t390 = load ptr, ptr @stdout, align 8
  %t391 = call i32 @fputs(ptr %t389, ptr %t390)
  br label %cond.end23
cond.end23:
  %t392 = load ptr, ptr @g-def-bufp, align 8
  %t393 = icmp ne ptr %t392, null
  store i1 %t393, ptr %and.val26, align 1
  br i1 %t393, label %and.rhs26, label %and.end26
and.rhs26:
  %t394 = load ptr, ptr @g-def-bufp, align 8
  %t395 = sext i32 0 to i64
  %t396 = call i32 @char-at(ptr %t394, i64 %t395)
  %t397 = icmp ne i32 %t396, 0
  store i1 %t397, ptr %and.val26, align 1
  br label %and.end26
and.end26:
  %t398 = load i1, ptr %and.val26, align 1
  br i1 %t398, label %cond.then25.0, label %cond.end25
cond.then25.0:
  %t399 = load ptr, ptr @g-def-bufp, align 8
  %t400 = load ptr, ptr @stdout, align 8
  %t401 = call i32 @fputs(ptr %t399, ptr %t400)
  br label %cond.end25
cond.end25:
  %t402 = load ptr, ptr @g-type-bufp, align 8
  call void @free(ptr %t402)
  %t403 = load ptr, ptr @g-decl-bufp, align 8
  call void @free(ptr %t403)
  %t404 = load ptr, ptr @g-def-bufp, align 8
  call void @free(ptr %t404)
  ret i32 0
}

