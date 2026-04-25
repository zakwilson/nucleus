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

%BinOp = type { ptr, ptr, ptr, i32 }

%Vec = type { ptr, i32, i32 }

%MacroDef = type { ptr, ptr, i32, i32 }

%RMacro = type { ptr, i32, ptr }

@.str.0 = private unnamed_addr constant [5 x i8] c"cond\00", align 1
@.str.1 = private unnamed_addr constant [5 x i8] c"true\00", align 1
@.str.2 = private unnamed_addr constant [5 x i8] c"cond\00", align 1
@.str.3 = private unnamed_addr constant [3 x i8] c"do\00", align 1
@.str.4 = private unnamed_addr constant [5 x i8] c"cond\00", align 1
@.str.5 = private unnamed_addr constant [4 x i8] c"not\00", align 1
@.str.6 = private unnamed_addr constant [3 x i8] c"do\00", align 1
@.str.7 = private unnamed_addr constant [2 x i8] c"=\00", align 1
@.str.8 = private unnamed_addr constant [2 x i8] c"=\00", align 1
@.str.9 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.10 = private unnamed_addr constant [4 x i8] c"let\00", align 1
@.str.11 = private unnamed_addr constant [6 x i8] c"while\00", align 1
@.str.12 = private unnamed_addr constant [4 x i8] c"let\00", align 1
@.str.13 = private unnamed_addr constant [6 x i8] c"while\00", align 1
@.str.14 = private unnamed_addr constant [2 x i8] c"<\00", align 1
@.str.15 = private unnamed_addr constant [5 x i8] c"inc!\00", align 1
@.str.16 = private unnamed_addr constant [2 x i8] c"_\00", align 1
@.str.17 = private unnamed_addr constant [2 x i8] c"_\00", align 1
@.str.18 = private unnamed_addr constant [13 x i8] c"arena malloc\00", align 1
@.str.19 = private unnamed_addr constant [11 x i8] c"arena grow\00", align 1
@.str.20 = private unnamed_addr constant [8 x i8] c"__gs_%d\00", align 1
@.str.21 = private unnamed_addr constant [18 x i8] c"%s:%d: error: %s\0A\00", align 1
@.str.22 = private unnamed_addr constant [28 x i8] c"unterminated string literal\00", align 1
@.str.23 = private unnamed_addr constant [19 x i8] c"unknown escape \5C%c\00", align 1
@.str.24 = private unnamed_addr constant [24 x i8] c"string literal too long\00", align 1
@.str.25 = private unnamed_addr constant [25 x i8] c"integer literal too long\00", align 1
@.str.26 = private unnamed_addr constant [13 x i8] c"unexpected )\00", align 1
@.str.27 = private unnamed_addr constant [24 x i8] c"unexpected end of input\00", align 1
@.str.28 = private unnamed_addr constant [18 x i8] c"unterminated list\00", align 1
@.str.29 = private unnamed_addr constant [3 x i8] c"()\00", align 1
@.str.30 = private unnamed_addr constant [4 x i8] c"%ld\00", align 1
@.str.31 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.32 = private unnamed_addr constant [3 x i8] c"i1\00", align 1
@.str.33 = private unnamed_addr constant [3 x i8] c"i8\00", align 1
@.str.34 = private unnamed_addr constant [4 x i8] c"i16\00", align 1
@.str.35 = private unnamed_addr constant [4 x i8] c"i32\00", align 1
@.str.36 = private unnamed_addr constant [4 x i8] c"i64\00", align 1
@.str.37 = private unnamed_addr constant [3 x i8] c"i8\00", align 1
@.str.38 = private unnamed_addr constant [4 x i8] c"i16\00", align 1
@.str.39 = private unnamed_addr constant [4 x i8] c"i32\00", align 1
@.str.40 = private unnamed_addr constant [4 x i8] c"i64\00", align 1
@.str.41 = private unnamed_addr constant [4 x i8] c"ptr\00", align 1
@.str.42 = private unnamed_addr constant [4 x i8] c"ptr\00", align 1
@.str.43 = private unnamed_addr constant [5 x i8] c"%%%s\00", align 1
@.str.44 = private unnamed_addr constant [2 x i8] c"?\00", align 1
@.str.45 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.46 = private unnamed_addr constant [6 x i8] c"_Bool\00", align 1
@.str.47 = private unnamed_addr constant [7 x i8] c"int8_t\00", align 1
@.str.48 = private unnamed_addr constant [8 x i8] c"int16_t\00", align 1
@.str.49 = private unnamed_addr constant [8 x i8] c"int32_t\00", align 1
@.str.50 = private unnamed_addr constant [8 x i8] c"int64_t\00", align 1
@.str.51 = private unnamed_addr constant [8 x i8] c"uint8_t\00", align 1
@.str.52 = private unnamed_addr constant [9 x i8] c"uint16_t\00", align 1
@.str.53 = private unnamed_addr constant [9 x i8] c"uint32_t\00", align 1
@.str.54 = private unnamed_addr constant [9 x i8] c"uint64_t\00", align 1
@.str.55 = private unnamed_addr constant [6 x i8] c"void*\00", align 1
@.str.56 = private unnamed_addr constant [6 x i8] c"void*\00", align 1
@.str.57 = private unnamed_addr constant [10 x i8] c"struct %s\00", align 1
@.str.58 = private unnamed_addr constant [14 x i8] c"/* unknown */\00", align 1
@.str.59 = private unnamed_addr constant [6 x i8] c"trunc\00", align 1
@.str.60 = private unnamed_addr constant [5 x i8] c"zext\00", align 1
@.str.61 = private unnamed_addr constant [5 x i8] c"sext\00", align 1
@.str.62 = private unnamed_addr constant [23 x i8] c"  %s = %s %s %s to %s\0A\00", align 1
@.str.63 = private unnamed_addr constant [28 x i8] c"nucleusc: too many structs\0A\00", align 1
@.str.64 = private unnamed_addr constant [4 x i8] c"int\00", align 1
@.str.65 = private unnamed_addr constant [3 x i8] c"i1\00", align 1
@.str.66 = private unnamed_addr constant [3 x i8] c"i8\00", align 1
@.str.67 = private unnamed_addr constant [4 x i8] c"i16\00", align 1
@.str.68 = private unnamed_addr constant [4 x i8] c"i32\00", align 1
@.str.69 = private unnamed_addr constant [4 x i8] c"i64\00", align 1
@.str.70 = private unnamed_addr constant [5 x i8] c"bool\00", align 1
@.str.71 = private unnamed_addr constant [4 x i8] c"ptr\00", align 1
@.str.72 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.73 = private unnamed_addr constant [4 x i8] c"ui8\00", align 1
@.str.74 = private unnamed_addr constant [5 x i8] c"ui16\00", align 1
@.str.75 = private unnamed_addr constant [5 x i8] c"ui32\00", align 1
@.str.76 = private unnamed_addr constant [5 x i8] c"ui64\00", align 1
@.str.77 = private unnamed_addr constant [17 x i8] c"unknown type: %s\00", align 1
@.str.78 = private unnamed_addr constant [3 x i8] c"fn\00", align 1
@.str.79 = private unnamed_addr constant [3 x i8] c"fn\00", align 1
@.str.80 = private unnamed_addr constant [32 x i8] c"unable to parse type expression\00", align 1
@.str.81 = private unnamed_addr constant [7 x i8] c"malloc\00", align 1
@.str.82 = private unnamed_addr constant [6 x i8] c"%%t%d\00", align 1
@.str.83 = private unnamed_addr constant [4 x i8] c"%ld\00", align 1
@.str.84 = private unnamed_addr constant [69 x i8] c"  %s = getelementptr inbounds [%d x i8], ptr @.str.%d, i64 0, i64 0\0A\00", align 1
@.str.85 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.86 = private unnamed_addr constant [138 x i8] c"@.q%d = private unnamed_addr constant { i32, i32, i64, ptr, ptr, ptr } { i32 0, i32 %d, i64 %ld, ptr null, ptr null, ptr null }, align 8\0A\00", align 1
@.str.87 = private unnamed_addr constant [7 x i8] c"@.q%ld\00", align 1
@.str.88 = private unnamed_addr constant [195 x i8] c"@.q%d = private unnamed_addr constant { i32, i32, i64, ptr, ptr, ptr } { i32 %d, i32 %d, i64 0, ptr getelementptr inbounds ([%d x i8], ptr @.str.%d, i64 0, i64 0), ptr null, ptr null }, align 8\0A\00", align 1
@.str.89 = private unnamed_addr constant [7 x i8] c"@.q%ld\00", align 1
@.str.90 = private unnamed_addr constant [132 x i8] c"@.q%d = private unnamed_addr constant { i32, i32, i64, ptr, ptr, ptr } { i32 3, i32 %d, i64 0, ptr null, ptr %s, ptr %s }, align 8\0A\00", align 1
@.str.91 = private unnamed_addr constant [7 x i8] c"@.q%ld\00", align 1
@.str.92 = private unnamed_addr constant [21 x i8] c"quote: expects 1 arg\00", align 1
@.str.93 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.94 = private unnamed_addr constant [15 x i8] c"unquote-splice\00", align 1
@.str.95 = private unnamed_addr constant [43 x i8] c"  %s = call ptr @__append(ptr %s, ptr %s)\0A\00", align 1
@.str.96 = private unnamed_addr constant [41 x i8] c"  %s = call ptr @__cons(ptr %s, ptr %s)\0A\00", align 1
@.str.97 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.98 = private unnamed_addr constant [8 x i8] c"unquote\00", align 1
@.str.99 = private unnamed_addr constant [15 x i8] c"unquote-splice\00", align 1
@.str.100 = private unnamed_addr constant [28 x i8] c"unquote-splice outside list\00", align 1
@.str.101 = private unnamed_addr constant [26 x i8] c"quasiquote: expects 1 arg\00", align 1
@.str.102 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.103 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.104 = private unnamed_addr constant [5 x i8] c"true\00", align 1
@.str.105 = private unnamed_addr constant [2 x i8] c"1\00", align 1
@.str.106 = private unnamed_addr constant [6 x i8] c"false\00", align 1
@.str.107 = private unnamed_addr constant [2 x i8] c"0\00", align 1
@.str.108 = private unnamed_addr constant [14 x i8] c"undefined: %s\00", align 1
@.str.109 = private unnamed_addr constant [25 x i8] c"cannot use '%s' as value\00", align 1
@.str.110 = private unnamed_addr constant [34 x i8] c"  %s = load %s, ptr %s, align %d\0A\00", align 1
@.str.111 = private unnamed_addr constant [2 x i8] c"+\00", align 1
@.str.112 = private unnamed_addr constant [8 x i8] c"add nsw\00", align 1
@.str.113 = private unnamed_addr constant [4 x i8] c"add\00", align 1
@.str.114 = private unnamed_addr constant [2 x i8] c"-\00", align 1
@.str.115 = private unnamed_addr constant [8 x i8] c"sub nsw\00", align 1
@.str.116 = private unnamed_addr constant [4 x i8] c"sub\00", align 1
@.str.117 = private unnamed_addr constant [2 x i8] c"*\00", align 1
@.str.118 = private unnamed_addr constant [8 x i8] c"mul nsw\00", align 1
@.str.119 = private unnamed_addr constant [4 x i8] c"mul\00", align 1
@.str.120 = private unnamed_addr constant [2 x i8] c"/\00", align 1
@.str.121 = private unnamed_addr constant [5 x i8] c"sdiv\00", align 1
@.str.122 = private unnamed_addr constant [5 x i8] c"udiv\00", align 1
@.str.123 = private unnamed_addr constant [2 x i8] c"%\00", align 1
@.str.124 = private unnamed_addr constant [5 x i8] c"srem\00", align 1
@.str.125 = private unnamed_addr constant [5 x i8] c"urem\00", align 1
@.str.126 = private unnamed_addr constant [8 x i8] c"bit-and\00", align 1
@.str.127 = private unnamed_addr constant [4 x i8] c"and\00", align 1
@.str.128 = private unnamed_addr constant [4 x i8] c"and\00", align 1
@.str.129 = private unnamed_addr constant [7 x i8] c"bit-or\00", align 1
@.str.130 = private unnamed_addr constant [3 x i8] c"or\00", align 1
@.str.131 = private unnamed_addr constant [3 x i8] c"or\00", align 1
@.str.132 = private unnamed_addr constant [8 x i8] c"bit-xor\00", align 1
@.str.133 = private unnamed_addr constant [4 x i8] c"xor\00", align 1
@.str.134 = private unnamed_addr constant [4 x i8] c"xor\00", align 1
@.str.135 = private unnamed_addr constant [8 x i8] c"bit-shl\00", align 1
@.str.136 = private unnamed_addr constant [4 x i8] c"shl\00", align 1
@.str.137 = private unnamed_addr constant [4 x i8] c"shl\00", align 1
@.str.138 = private unnamed_addr constant [8 x i8] c"bit-shr\00", align 1
@.str.139 = private unnamed_addr constant [5 x i8] c"ashr\00", align 1
@.str.140 = private unnamed_addr constant [5 x i8] c"lshr\00", align 1
@.str.141 = private unnamed_addr constant [2 x i8] c"=\00", align 1
@.str.142 = private unnamed_addr constant [8 x i8] c"icmp eq\00", align 1
@.str.143 = private unnamed_addr constant [8 x i8] c"icmp eq\00", align 1
@.str.144 = private unnamed_addr constant [3 x i8] c"!=\00", align 1
@.str.145 = private unnamed_addr constant [8 x i8] c"icmp ne\00", align 1
@.str.146 = private unnamed_addr constant [8 x i8] c"icmp ne\00", align 1
@.str.147 = private unnamed_addr constant [2 x i8] c"<\00", align 1
@.str.148 = private unnamed_addr constant [9 x i8] c"icmp slt\00", align 1
@.str.149 = private unnamed_addr constant [9 x i8] c"icmp ult\00", align 1
@.str.150 = private unnamed_addr constant [3 x i8] c"<=\00", align 1
@.str.151 = private unnamed_addr constant [9 x i8] c"icmp sle\00", align 1
@.str.152 = private unnamed_addr constant [9 x i8] c"icmp ule\00", align 1
@.str.153 = private unnamed_addr constant [2 x i8] c">\00", align 1
@.str.154 = private unnamed_addr constant [9 x i8] c"icmp sgt\00", align 1
@.str.155 = private unnamed_addr constant [9 x i8] c"icmp ugt\00", align 1
@.str.156 = private unnamed_addr constant [3 x i8] c">=\00", align 1
@.str.157 = private unnamed_addr constant [9 x i8] c"icmp sge\00", align 1
@.str.158 = private unnamed_addr constant [9 x i8] c"icmp uge\00", align 1
@.str.159 = private unnamed_addr constant [18 x i8] c"%s expects 2 args\00", align 1
@.str.160 = private unnamed_addr constant [22 x i8] c"  %s = %s ptr %s, %s\0A\00", align 1
@.str.161 = private unnamed_addr constant [28 x i8] c"%s expects integer operands\00", align 1
@.str.162 = private unnamed_addr constant [57 x i8] c"%s: mixed signed/unsigned operands \E2\80\94 use explicit cast\00", align 1
@.str.163 = private unnamed_addr constant [25 x i8] c"%s operand type mismatch\00", align 1
@.str.164 = private unnamed_addr constant [21 x i8] c"  %s = %s %s %s, %s\0A\00", align 1
@.str.165 = private unnamed_addr constant [20 x i8] c"cast expects 2 args\00", align 1
@.str.166 = private unnamed_addr constant [35 x i8] c"cast: target type must be a symbol\00", align 1
@.str.167 = private unnamed_addr constant [6 x i8] c"trunc\00", align 1
@.str.168 = private unnamed_addr constant [5 x i8] c"zext\00", align 1
@.str.169 = private unnamed_addr constant [5 x i8] c"sext\00", align 1
@.str.170 = private unnamed_addr constant [9 x i8] c"inttoptr\00", align 1
@.str.171 = private unnamed_addr constant [9 x i8] c"ptrtoint\00", align 1
@.str.172 = private unnamed_addr constant [29 x i8] c"cast: unsupported conversion\00", align 1
@.str.173 = private unnamed_addr constant [23 x i8] c"  %s = %s %s %s to %s\0A\00", align 1
@.str.174 = private unnamed_addr constant [17 x i8] c". expects 2 args\00", align 1
@.str.175 = private unnamed_addr constant [37 x i8] c".: operand must be pointer to struct\00", align 1
@.str.176 = private unnamed_addr constant [29 x i8] c".: field name must be symbol\00", align 1
@.str.177 = private unnamed_addr constant [32 x i8] c".: no field '%s' on struct '%s'\00", align 1
@.str.178 = private unnamed_addr constant [59 x i8] c"  %s = getelementptr inbounds %%%s, ptr %s, i32 0, i32 %d\0A\00", align 1
@.str.179 = private unnamed_addr constant [34 x i8] c"  %s = load %s, ptr %s, align %d\0A\00", align 1
@.str.180 = private unnamed_addr constant [21 x i8] c".set! expects 3 args\00", align 1
@.str.181 = private unnamed_addr constant [41 x i8] c".set!: operand must be pointer to struct\00", align 1
@.str.182 = private unnamed_addr constant [33 x i8] c".set!: field name must be symbol\00", align 1
@.str.183 = private unnamed_addr constant [36 x i8] c".set!: no field '%s' on struct '%s'\00", align 1
@.str.184 = private unnamed_addr constant [36 x i8] c".set!: type mismatch for field '%s'\00", align 1
@.str.185 = private unnamed_addr constant [59 x i8] c"  %s = getelementptr inbounds %%%s, ptr %s, i32 0, i32 %d\0A\00", align 1
@.str.186 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.187 = private unnamed_addr constant [21 x i8] c"sizeof expects 1 arg\00", align 1
@.str.188 = private unnamed_addr constant [30 x i8] c"sizeof: arg must be type name\00", align 1
@.str.189 = private unnamed_addr constant [42 x i8] c"  %s = getelementptr %s, ptr null, i32 1\0A\00", align 1
@.str.190 = private unnamed_addr constant [31 x i8] c"  %s = ptrtoint ptr %s to i64\0A\00", align 1
@.str.191 = private unnamed_addr constant [27 x i8] c"alloca expects 1 or 2 args\00", align 1
@.str.192 = private unnamed_addr constant [36 x i8] c"alloca: first arg must be type name\00", align 1
@.str.193 = private unnamed_addr constant [36 x i8] c"  %s = alloca %s, i32 %s, align %d\0A\00", align 1
@.str.194 = private unnamed_addr constant [28 x i8] c"  %s = alloca %s, align %d\0A\00", align 1
@.str.195 = private unnamed_addr constant [20 x i8] c"aref expects 2 args\00", align 1
@.str.196 = private unnamed_addr constant [36 x i8] c"aref: operand must be typed pointer\00", align 1
@.str.197 = private unnamed_addr constant [28 x i8] c"aref: index must be integer\00", align 1
@.str.198 = private unnamed_addr constant [26 x i8] c"  %s = sext %s %s to i64\0A\00", align 1
@.str.199 = private unnamed_addr constant [50 x i8] c"  %s = getelementptr inbounds %s, ptr %s, i64 %s\0A\00", align 1
@.str.200 = private unnamed_addr constant [34 x i8] c"  %s = load %s, ptr %s, align %d\0A\00", align 1
@.str.201 = private unnamed_addr constant [21 x i8] c"aset! expects 3 args\00", align 1
@.str.202 = private unnamed_addr constant [37 x i8] c"aset!: operand must be typed pointer\00", align 1
@.str.203 = private unnamed_addr constant [29 x i8] c"aset!: index must be integer\00", align 1
@.str.204 = private unnamed_addr constant [26 x i8] c"  %s = sext %s %s to i64\0A\00", align 1
@.str.205 = private unnamed_addr constant [27 x i8] c"aset!: value type mismatch\00", align 1
@.str.206 = private unnamed_addr constant [50 x i8] c"  %s = getelementptr inbounds %s, ptr %s, i64 %s\0A\00", align 1
@.str.207 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.208 = private unnamed_addr constant [19 x i8] c"char expects 1 arg\00", align 1
@.str.209 = private unnamed_addr constant [37 x i8] c"char: arg must be single-char string\00", align 1
@.str.210 = private unnamed_addr constant [3 x i8] c"%d\00", align 1
@.str.211 = private unnamed_addr constant [22 x i8] c"addr-of expects 1 arg\00", align 1
@.str.212 = private unnamed_addr constant [31 x i8] c"addr-of: target must be symbol\00", align 1
@.str.213 = private unnamed_addr constant [24 x i8] c"addr-of: undefined '%s'\00", align 1
@.str.214 = private unnamed_addr constant [46 x i8] c"addr-of: cannot take address of function '%s'\00", align 1
@.str.215 = private unnamed_addr constant [27 x i8] c"funcall-void expects 1 arg\00", align 1
@.str.216 = private unnamed_addr constant [30 x i8] c"funcall-void: arg must be ptr\00", align 1
@.str.217 = private unnamed_addr constant [18 x i8] c"  call void %s()\0A\00", align 1
@.str.218 = private unnamed_addr constant [29 x i8] c"funcall-ptr-1 expects 2 args\00", align 1
@.str.219 = private unnamed_addr constant [30 x i8] c"funcall-ptr-1: fn must be ptr\00", align 1
@.str.220 = private unnamed_addr constant [31 x i8] c"funcall-ptr-1: arg must be ptr\00", align 1
@.str.221 = private unnamed_addr constant [28 x i8] c"  %s = call ptr %s(ptr %s)\0A\00", align 1
@.str.222 = private unnamed_addr constant [30 x i8] c"funcall-ptr-i32 expects 1 arg\00", align 1
@.str.223 = private unnamed_addr constant [33 x i8] c"funcall-ptr-i32: arg must be ptr\00", align 1
@.str.224 = private unnamed_addr constant [22 x i8] c"  %s = call i32 %s()\0A\00", align 1
@.str.225 = private unnamed_addr constant [30 x i8] c"funcall-ptr-i64 expects 1 arg\00", align 1
@.str.226 = private unnamed_addr constant [33 x i8] c"funcall-ptr-i64: arg must be ptr\00", align 1
@.str.227 = private unnamed_addr constant [22 x i8] c"  %s = call i64 %s()\0A\00", align 1
@.str.228 = private unnamed_addr constant [30 x i8] c"funcall-ptr-ptr expects 1 arg\00", align 1
@.str.229 = private unnamed_addr constant [33 x i8] c"funcall-ptr-ptr: arg must be ptr\00", align 1
@.str.230 = private unnamed_addr constant [22 x i8] c"  %s = call ptr %s()\0A\00", align 1
@.str.231 = private unnamed_addr constant [31 x i8] c"funcall expects at least 1 arg\00", align 1
@.str.232 = private unnamed_addr constant [46 x i8] c"funcall: first arg must be a function pointer\00", align 1
@.str.233 = private unnamed_addr constant [34 x i8] c"funcall: expected %d args, got %d\00", align 1
@.str.234 = private unnamed_addr constant [16 x i8] c"  call void %s(\00", align 1
@.str.235 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.236 = private unnamed_addr constant [6 x i8] c"%s %s\00", align 1
@.str.237 = private unnamed_addr constant [3 x i8] c")\0A\00", align 1
@.str.238 = private unnamed_addr constant [19 x i8] c"  %s = call %s %s(\00", align 1
@.str.239 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.240 = private unnamed_addr constant [6 x i8] c"%s %s\00", align 1
@.str.241 = private unnamed_addr constant [3 x i8] c")\0A\00", align 1
@.str.242 = private unnamed_addr constant [20 x i8] c"deref expects 1 arg\00", align 1
@.str.243 = private unnamed_addr constant [37 x i8] c"deref: operand must be typed pointer\00", align 1
@.str.244 = private unnamed_addr constant [34 x i8] c"  %s = load %s, ptr %s, align %d\0A\00", align 1
@.str.245 = private unnamed_addr constant [24 x i8] c"ptr-set! expects 2 args\00", align 1
@.str.246 = private unnamed_addr constant [40 x i8] c"ptr-set!: operand must be typed pointer\00", align 1
@.str.247 = private unnamed_addr constant [30 x i8] c"ptr-set!: value type mismatch\00", align 1
@.str.248 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.249 = private unnamed_addr constant [20 x i8] c"ptr+ expects 2 args\00", align 1
@.str.250 = private unnamed_addr constant [36 x i8] c"ptr+: operand must be typed pointer\00", align 1
@.str.251 = private unnamed_addr constant [29 x i8] c"ptr+: offset must be integer\00", align 1
@.str.252 = private unnamed_addr constant [26 x i8] c"  %s = sext %s %s to i64\0A\00", align 1
@.str.253 = private unnamed_addr constant [50 x i8] c"  %s = getelementptr inbounds %s, ptr %s, i64 %s\0A\00", align 1
@.str.254 = private unnamed_addr constant [18 x i8] c"not expects 1 arg\00", align 1
@.str.255 = private unnamed_addr constant [23 x i8] c"not expects i1 operand\00", align 1
@.str.256 = private unnamed_addr constant [21 x i8] c"  %s = xor i1 %s, 1\0A\00", align 1
@.str.257 = private unnamed_addr constant [3 x i8] c"or\00", align 1
@.str.258 = private unnamed_addr constant [4 x i8] c"and\00", align 1
@.str.259 = private unnamed_addr constant [18 x i8] c"%s expects 2 args\00", align 1
@.str.260 = private unnamed_addr constant [9 x i8] c"%s.rhs%d\00", align 1
@.str.261 = private unnamed_addr constant [9 x i8] c"%s.end%d\00", align 1
@.str.262 = private unnamed_addr constant [11 x i8] c"%%%s.val%d\00", align 1
@.str.263 = private unnamed_addr constant [27 x i8] c"  %s = alloca i1, align 1\0A\00", align 1
@.str.264 = private unnamed_addr constant [23 x i8] c"%s expects i1 operands\00", align 1
@.str.265 = private unnamed_addr constant [32 x i8] c"  store i1 %s, ptr %s, align 1\0A\00", align 1
@.str.266 = private unnamed_addr constant [36 x i8] c"  br i1 %s, label %%%s, label %%%s\0A\00", align 1
@.str.267 = private unnamed_addr constant [36 x i8] c"  br i1 %s, label %%%s, label %%%s\0A\00", align 1
@.str.268 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.269 = private unnamed_addr constant [23 x i8] c"%s expects i1 operands\00", align 1
@.str.270 = private unnamed_addr constant [32 x i8] c"  store i1 %s, ptr %s, align 1\0A\00", align 1
@.str.271 = private unnamed_addr constant [17 x i8] c"  br label %%%s\0A\00", align 1
@.str.272 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.273 = private unnamed_addr constant [33 x i8] c"  %s = load i1, ptr %s, align 1\0A\00", align 1
@.str.274 = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.275 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.276 = private unnamed_addr constant [8 x i8] c"%s%s %s\00", align 1
@.str.277 = private unnamed_addr constant [19 x i8] c"not a function: %s\00", align 1
@.str.278 = private unnamed_addr constant [5 x i8] c"%s (\00", align 1
@.str.279 = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.280 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.281 = private unnamed_addr constant [5 x i8] c"%s%s\00", align 1
@.str.282 = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.283 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.284 = private unnamed_addr constant [7 x i8] c"%s...)\00", align 1
@.str.285 = private unnamed_addr constant [18 x i8] c"  call %s %s(%s)\0A\00", align 1
@.str.286 = private unnamed_addr constant [23 x i8] c"  %s = call %s %s(%s)\0A\00", align 1
@.str.287 = private unnamed_addr constant [18 x i8] c"  call %s %s(%s)\0A\00", align 1
@.str.288 = private unnamed_addr constant [23 x i8] c"  %s = call %s %s(%s)\0A\00", align 1
@.str.289 = private unnamed_addr constant [12 x i8] c"  ret void\0A\00", align 1
@.str.290 = private unnamed_addr constant [27 x i8] c"return expects 0 or 1 args\00", align 1
@.str.291 = private unnamed_addr constant [13 x i8] c"  ret %s %s\0A\00", align 1
@.str.292 = private unnamed_addr constant [14 x i8] c"let: bad form\00", align 1
@.str.293 = private unnamed_addr constant [31 x i8] c"let: binding list must be even\00", align 1
@.str.294 = private unnamed_addr constant [27 x i8] c"let: missing :type on '%s'\00", align 1
@.str.295 = private unnamed_addr constant [13 x i8] c"%%%s.addr.%d\00", align 1
@.str.296 = private unnamed_addr constant [28 x i8] c"  %s = alloca %s, align %d\0A\00", align 1
@.str.297 = private unnamed_addr constant [33 x i8] c"let: init type mismatch for '%s'\00", align 1
@.str.298 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.299 = private unnamed_addr constant [35 x i8] c"cond: expects pairs of (test body)\00", align 1
@.str.300 = private unnamed_addr constant [11 x i8] c"cond.end%d\00", align 1
@.str.301 = private unnamed_addr constant [15 x i8] c"cond.then%d.%d\00", align 1
@.str.302 = private unnamed_addr constant [15 x i8] c"cond.test%d.%d\00", align 1
@.str.303 = private unnamed_addr constant [22 x i8] c"cond: test must be i1\00", align 1
@.str.304 = private unnamed_addr constant [36 x i8] c"  br i1 %s, label %%%s, label %%%s\0A\00", align 1
@.str.305 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.306 = private unnamed_addr constant [17 x i8] c"  br label %%%s\0A\00", align 1
@.str.307 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.308 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.309 = private unnamed_addr constant [25 x i8] c"while: missing condition\00", align 1
@.str.310 = private unnamed_addr constant [13 x i8] c"while.cond%d\00", align 1
@.str.311 = private unnamed_addr constant [13 x i8] c"while.body%d\00", align 1
@.str.312 = private unnamed_addr constant [12 x i8] c"while.end%d\00", align 1
@.str.313 = private unnamed_addr constant [17 x i8] c"  br label %%%s\0A\00", align 1
@.str.314 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.315 = private unnamed_addr constant [27 x i8] c"while condition must be i1\00", align 1
@.str.316 = private unnamed_addr constant [36 x i8] c"  br i1 %s, label %%%s, label %%%s\0A\00", align 1
@.str.317 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.318 = private unnamed_addr constant [17 x i8] c"  br label %%%s\0A\00", align 1
@.str.319 = private unnamed_addr constant [5 x i8] c"%s:\0A\00", align 1
@.str.320 = private unnamed_addr constant [20 x i8] c"set! expects 2 args\00", align 1
@.str.321 = private unnamed_addr constant [28 x i8] c"set!: target must be symbol\00", align 1
@.str.322 = private unnamed_addr constant [27 x i8] c"set!: undefined local '%s'\00", align 1
@.str.323 = private unnamed_addr constant [29 x i8] c"set!: type mismatch for '%s'\00", align 1
@.str.324 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.325 = private unnamed_addr constant [19 x i8] c"inc! expects 1 arg\00", align 1
@.str.326 = private unnamed_addr constant [28 x i8] c"inc!: target must be symbol\00", align 1
@.str.327 = private unnamed_addr constant [27 x i8] c"inc!: undefined local '%s'\00", align 1
@.str.328 = private unnamed_addr constant [22 x i8] c"inc!: must be integer\00", align 1
@.str.329 = private unnamed_addr constant [34 x i8] c"  %s = load %s, ptr %s, align %d\0A\00", align 1
@.str.330 = private unnamed_addr constant [25 x i8] c"  %s = add nsw %s %s, 1\0A\00", align 1
@.str.331 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.332 = private unnamed_addr constant [23 x i8] c"macro: not enough args\00", align 1
@.str.333 = private unnamed_addr constant [28 x i8] c"macro: wrong number of args\00", align 1
@.str.334 = private unnamed_addr constant [35 x i8] c"%s: macro '%s': JIT lookup failed\0A\00", align 1
@.str.335 = private unnamed_addr constant [40 x i8] c"%s: macro '%s': JIT function not found\0A\00", align 1
@.str.336 = private unnamed_addr constant [31 x i8] c"%s: macro '%s': returned null\0A\00", align 1
@.str.337 = private unnamed_addr constant [11 x i8] c"empty list\00", align 1
@.str.338 = private unnamed_addr constant [25 x i8] c"list head must be symbol\00", align 1
@.str.339 = private unnamed_addr constant [7 x i8] c"gensym\00", align 1
@.str.340 = private unnamed_addr constant [35 x i8] c"  %s = call ptr @nucleus_gensym()\0A\00", align 1
@.str.341 = private unnamed_addr constant [14 x i8] c"funcall-ptr-1\00", align 1
@.str.342 = private unnamed_addr constant [16 x i8] c"funcall-ptr-i32\00", align 1
@.str.343 = private unnamed_addr constant [16 x i8] c"funcall-ptr-i64\00", align 1
@.str.344 = private unnamed_addr constant [16 x i8] c"funcall-ptr-ptr\00", align 1
@.str.345 = private unnamed_addr constant [7 x i8] c"return\00", align 1
@.str.346 = private unnamed_addr constant [3 x i8] c"do\00", align 1
@.str.347 = private unnamed_addr constant [4 x i8] c"let\00", align 1
@.str.348 = private unnamed_addr constant [5 x i8] c"cond\00", align 1
@.str.349 = private unnamed_addr constant [6 x i8] c"quote\00", align 1
@.str.350 = private unnamed_addr constant [11 x i8] c"quasiquote\00", align 1
@.str.351 = private unnamed_addr constant [6 x i8] c"while\00", align 1
@.str.352 = private unnamed_addr constant [5 x i8] c"set!\00", align 1
@.str.353 = private unnamed_addr constant [5 x i8] c"inc!\00", align 1
@.str.354 = private unnamed_addr constant [4 x i8] c"not\00", align 1
@.str.355 = private unnamed_addr constant [4 x i8] c"and\00", align 1
@.str.356 = private unnamed_addr constant [3 x i8] c"or\00", align 1
@.str.357 = private unnamed_addr constant [5 x i8] c"cast\00", align 1
@.str.358 = private unnamed_addr constant [8 x i8] c"addr-of\00", align 1
@.str.359 = private unnamed_addr constant [13 x i8] c"funcall-void\00", align 1
@.str.360 = private unnamed_addr constant [8 x i8] c"funcall\00", align 1
@.str.361 = private unnamed_addr constant [6 x i8] c"deref\00", align 1
@.str.362 = private unnamed_addr constant [9 x i8] c"ptr-set!\00", align 1
@.str.363 = private unnamed_addr constant [5 x i8] c"ptr+\00", align 1
@.str.364 = private unnamed_addr constant [2 x i8] c".\00", align 1
@.str.365 = private unnamed_addr constant [6 x i8] c".set!\00", align 1
@.str.366 = private unnamed_addr constant [7 x i8] c"sizeof\00", align 1
@.str.367 = private unnamed_addr constant [7 x i8] c"alloca\00", align 1
@.str.368 = private unnamed_addr constant [5 x i8] c"char\00", align 1
@.str.369 = private unnamed_addr constant [5 x i8] c"aref\00", align 1
@.str.370 = private unnamed_addr constant [6 x i8] c"aset!\00", align 1
@.str.371 = private unnamed_addr constant [12 x i8] c"unknown: %s\00", align 1
@.str.372 = private unnamed_addr constant [39 x i8] c"defvar: expects name and optional init\00", align 1
@.str.373 = private unnamed_addr constant [30 x i8] c"defvar: missing :type on '%s'\00", align 1
@.str.374 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.375 = private unnamed_addr constant [37 x i8] c"defvar: init must be integer literal\00", align 1
@.str.376 = private unnamed_addr constant [31 x i8] c"%s = global %s %ld, align %d\0A\0A\00", align 1
@.str.377 = private unnamed_addr constant [2 x i8] c"0\00", align 1
@.str.378 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.379 = private unnamed_addr constant [30 x i8] c"%s = global %s %s, align %d\0A\0A\00", align 1
@.str.380 = private unnamed_addr constant [33 x i8] c"defconst: expects name and value\00", align 1
@.str.381 = private unnamed_addr constant [30 x i8] c"defconst: name must be symbol\00", align 1
@.str.382 = private unnamed_addr constant [40 x i8] c"defconst: value must be integer literal\00", align 1
@.str.383 = private unnamed_addr constant [4 x i8] c"%ld\00", align 1
@.str.384 = private unnamed_addr constant [22 x i8] c"defenum: missing name\00", align 1
@.str.385 = private unnamed_addr constant [30 x i8] c"defenum: value must be symbol\00", align 1
@.str.386 = private unnamed_addr constant [3 x i8] c"%d\00", align 1
@.str.387 = private unnamed_addr constant [24 x i8] c"defstruct: missing name\00", align 1
@.str.388 = private unnamed_addr constant [31 x i8] c"defstruct: name must be symbol\00", align 1
@.str.389 = private unnamed_addr constant [36 x i8] c"defstruct: field '%s' missing :type\00", align 1
@.str.390 = private unnamed_addr constant [15 x i8] c"%%%s = type { \00", align 1
@.str.391 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.392 = private unnamed_addr constant [3 x i8] c"%s\00", align 1
@.str.393 = private unnamed_addr constant [5 x i8] c" }\0A\0A\00", align 1
@.str.394 = private unnamed_addr constant [26 x i8] c"extern: expects name:type\00", align 1
@.str.395 = private unnamed_addr constant [30 x i8] c"extern: missing :type on '%s'\00", align 1
@.str.396 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.397 = private unnamed_addr constant [26 x i8] c"%s = external global %s\0A\0A\00", align 1
@.str.398 = private unnamed_addr constant [28 x i8] c"include: expects one symbol\00", align 1
@.str.399 = private unnamed_addr constant [5 x i8] c"%s.h\00", align 1
@.str.400 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.401 = private unnamed_addr constant [6 x i8] c"_Bool\00", align 1
@.str.402 = private unnamed_addr constant [5 x i8] c"char\00", align 1
@.str.403 = private unnamed_addr constant [6 x i8] c"short\00", align 1
@.str.404 = private unnamed_addr constant [4 x i8] c"int\00", align 1
@.str.405 = private unnamed_addr constant [5 x i8] c"long\00", align 1
@.str.406 = private unnamed_addr constant [7 x i8] c"size_t\00", align 1
@.str.407 = private unnamed_addr constant [8 x i8] c"ssize_t\00", align 1
@.str.408 = private unnamed_addr constant [15 x i8] c"__gnuc_va_list\00", align 1
@.str.409 = private unnamed_addr constant [8 x i8] c"va_list\00", align 1
@.str.410 = private unnamed_addr constant [5 x i8] c"FILE\00", align 1
@.str.411 = private unnamed_addr constant [6 x i8] c"const\00", align 1
@.str.412 = private unnamed_addr constant [9 x i8] c"volatile\00", align 1
@.str.413 = private unnamed_addr constant [9 x i8] c"restrict\00", align 1
@.str.414 = private unnamed_addr constant [11 x i8] c"__restrict\00", align 1
@.str.415 = private unnamed_addr constant [8 x i8] c"_Atomic\00", align 1
@.str.416 = private unnamed_addr constant [7 x i8] c"extern\00", align 1
@.str.417 = private unnamed_addr constant [7 x i8] c"static\00", align 1
@.str.418 = private unnamed_addr constant [7 x i8] c"inline\00", align 1
@.str.419 = private unnamed_addr constant [9 x i8] c"__inline\00", align 1
@.str.420 = private unnamed_addr constant [11 x i8] c"__inline__\00", align 1
@.str.421 = private unnamed_addr constant [14 x i8] c"__extension__\00", align 1
@.str.422 = private unnamed_addr constant [9 x i8] c"unsigned\00", align 1
@.str.423 = private unnamed_addr constant [7 x i8] c"signed\00", align 1
@.str.424 = private unnamed_addr constant [5 x i8] c"long\00", align 1
@.str.425 = private unnamed_addr constant [5 x i8] c"long\00", align 1
@.str.426 = private unnamed_addr constant [4 x i8] c"int\00", align 1
@.str.427 = private unnamed_addr constant [5 x i8] c"long\00", align 1
@.str.428 = private unnamed_addr constant [5 x i8] c"char\00", align 1
@.str.429 = private unnamed_addr constant [5 x i8] c"long\00", align 1
@.str.430 = private unnamed_addr constant [6 x i8] c"short\00", align 1
@.str.431 = private unnamed_addr constant [7 x i8] c"struct\00", align 1
@.str.432 = private unnamed_addr constant [14 x i8] c"__attribute__\00", align 1
@.str.433 = private unnamed_addr constant [6 x i8] c"const\00", align 1
@.str.434 = private unnamed_addr constant [9 x i8] c"restrict\00", align 1
@.str.435 = private unnamed_addr constant [11 x i8] c"__restrict\00", align 1
@.str.436 = private unnamed_addr constant [4 x i8] c"int\00", align 1
@.str.437 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.438 = private unnamed_addr constant [14 x i8] c"__attribute__\00", align 1
@.str.439 = private unnamed_addr constant [8 x i8] c"__asm__\00", align 1
@.str.440 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.441 = private unnamed_addr constant [7 x i8] c"malloc\00", align 1
@.str.442 = private unnamed_addr constant [16 x i8] c"declare %s @%s(\00", align 1
@.str.443 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.444 = private unnamed_addr constant [3 x i8] c"%s\00", align 1
@.str.445 = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.446 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.447 = private unnamed_addr constant [6 x i8] c"%s...\00", align 1
@.str.448 = private unnamed_addr constant [3 x i8] c")\0A\00", align 1
@.str.449 = private unnamed_addr constant [2 x i8] c"r\00", align 1
@.str.450 = private unnamed_addr constant [48 x i8] c"clang -E -x c -include %s /dev/null 2>/dev/null\00", align 1
@.str.451 = private unnamed_addr constant [37 x i8] c"c-include: failed to preprocess '%s'\00", align 1
@.str.452 = private unnamed_addr constant [7 x i8] c"extern\00", align 1
@.str.453 = private unnamed_addr constant [2 x i8] c"\0A\00", align 1
@.str.454 = private unnamed_addr constant [15 x i8] c"defn: bad form\00", align 1
@.str.455 = private unnamed_addr constant [26 x i8] c"defn: params must be list\00", align 1
@.str.456 = private unnamed_addr constant [28 x i8] c"defn: missing :type on '%s'\00", align 1
@.str.457 = private unnamed_addr constant [34 x i8] c"defn: missing :type on param '%s'\00", align 1
@.str.458 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.459 = private unnamed_addr constant [10 x i8] c"%%%s.addr\00", align 1
@.str.460 = private unnamed_addr constant [9 x i8] c"%%%s.arg\00", align 1
@.str.461 = private unnamed_addr constant [28 x i8] c"  %s = alloca %s, align %d\0A\00", align 1
@.str.462 = private unnamed_addr constant [33 x i8] c"  store %s %s, ptr %s, align %d\0A\00", align 1
@.str.463 = private unnamed_addr constant [12 x i8] c"  ret void\0A\00", align 1
@.str.464 = private unnamed_addr constant [2 x i8] c"0\00", align 1
@.str.465 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.466 = private unnamed_addr constant [13 x i8] c"  ret %s %s\0A\00", align 1
@.str.467 = private unnamed_addr constant [15 x i8] c"define %s @%s(\00", align 1
@.str.468 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.469 = private unnamed_addr constant [12 x i8] c"%s %%%s.arg\00", align 1
@.str.470 = private unnamed_addr constant [5 x i8] c") {\0A\00", align 1
@.str.471 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.472 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.473 = private unnamed_addr constant [44 x i8] c"%s:%d: JIT error in LLVMOrcCreateLLJIT: %s\0A\00", align 1
@.str.474 = private unnamed_addr constant [47 x i8] c"%s:%d: JIT error in CreateDynLibSearchGen: %s\0A\00", align 1
@.str.475 = private unnamed_addr constant [15 x i8] c"<compile-time>\00", align 1
@.str.476 = private unnamed_addr constant [41 x i8] c"%s:%d: compile-time: IR parse error: %s\0A\00", align 1
@.str.477 = private unnamed_addr constant [41 x i8] c"%s:%d: JIT error in AddLLVMIRModule: %s\0A\00", align 1
@.str.478 = private unnamed_addr constant [46 x i8] c"compile-time: expected at least one body form\00", align 1
@.str.479 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.480 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.481 = private unnamed_addr constant [10 x i8] c"defstruct\00", align 1
@.str.482 = private unnamed_addr constant [9 x i8] c"defconst\00", align 1
@.str.483 = private unnamed_addr constant [8 x i8] c"defenum\00", align 1
@.str.484 = private unnamed_addr constant [7 x i8] c"defvar\00", align 1
@.str.485 = private unnamed_addr constant [8 x i8] c"include\00", align 1
@.str.486 = private unnamed_addr constant [7 x i8] c"extern\00", align 1
@.str.487 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.488 = private unnamed_addr constant [24 x i8] c"__compile_time_main_%ld\00", align 1
@.str.489 = private unnamed_addr constant [12 x i8] c"  ret void\0A\00", align 1
@.str.490 = private unnamed_addr constant [21 x i8] c"define void @%s() {\0A\00", align 1
@.str.491 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.492 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.493 = private unnamed_addr constant [26 x i8] c"declare ptr @malloc(i64)\0A\00", align 1
@.str.494 = private unnamed_addr constant [48 x i8] c"define private ptr @__cons(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.495 = private unnamed_addr constant [34 x i8] c"  %%c = call ptr @malloc(i64 40)\0A\00", align 1
@.str.496 = private unnamed_addr constant [89 x i8] c"  %%p0 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 0\0A\00", align 1
@.str.497 = private unnamed_addr constant [34 x i8] c"  store i32 3, ptr %%p0, align 8\0A\00", align 1
@.str.498 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 4\0A\00", align 1
@.str.499 = private unnamed_addr constant [36 x i8] c"  store ptr %%a, ptr %%p4, align 8\0A\00", align 1
@.str.500 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 5\0A\00", align 1
@.str.501 = private unnamed_addr constant [36 x i8] c"  store ptr %%b, ptr %%p5, align 8\0A\00", align 1
@.str.502 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.503 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.504 = private unnamed_addr constant [50 x i8] c"define private ptr @__append(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.505 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.506 = private unnamed_addr constant [31 x i8] c"  %%z = icmp eq ptr %%a, null\0A\00", align 1
@.str.507 = private unnamed_addr constant [39 x i8] c"  br i1 %%z, label %%nil, label %%rec\0A\00", align 1
@.str.508 = private unnamed_addr constant [6 x i8] c"nil:\0A\00", align 1
@.str.509 = private unnamed_addr constant [15 x i8] c"  ret ptr %%b\0A\00", align 1
@.str.510 = private unnamed_addr constant [6 x i8] c"rec:\0A\00", align 1
@.str.511 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 4\0A\00", align 1
@.str.512 = private unnamed_addr constant [39 x i8] c"  %%car = load ptr, ptr %%p4, align 8\0A\00", align 1
@.str.513 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 5\0A\00", align 1
@.str.514 = private unnamed_addr constant [39 x i8] c"  %%cdr = load ptr, ptr %%p5, align 8\0A\00", align 1
@.str.515 = private unnamed_addr constant [51 x i8] c"  %%rest = call ptr @__append(ptr %%cdr, ptr %%b)\0A\00", align 1
@.str.516 = private unnamed_addr constant [49 x i8] c"  %%c = call ptr @__cons(ptr %%car, ptr %%rest)\0A\00", align 1
@.str.517 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.518 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.519 = private unnamed_addr constant [31 x i8] c"; ModuleID = '<compile-time>'\0A\00", align 1
@.str.520 = private unnamed_addr constant [40 x i8] c"target triple = \22x86_64-pc-linux-gnu\22\0A\0A\00", align 1
@.str.521 = private unnamed_addr constant [41 x i8] c"defmacro: expects name, params, and body\00", align 1
@.str.522 = private unnamed_addr constant [30 x i8] c"defmacro: name must be symbol\00", align 1
@.str.523 = private unnamed_addr constant [32 x i8] c"defmacro: params must be a list\00", align 1
@.str.524 = private unnamed_addr constant [11 x i8] c"__macro_%s\00", align 1
@.str.525 = private unnamed_addr constant [6 x i8] c"&rest\00", align 1
@.str.526 = private unnamed_addr constant [45 x i8] c"defmacro: &rest must be second-to-last param\00", align 1
@.str.527 = private unnamed_addr constant [33 x i8] c"defmacro: param must be a symbol\00", align 1
@.str.528 = private unnamed_addr constant [6 x i8] c"&rest\00", align 1
@.str.529 = private unnamed_addr constant [27 x i8] c"defmacro: macro table full\00", align 1
@.str.530 = private unnamed_addr constant [39 x i8] c"  %%__args.addr = alloca ptr, align 8\0A\00", align 1
@.str.531 = private unnamed_addr constant [54 x i8] c"  store ptr %%__args.arg, ptr %%__args.addr, align 8\0A\00", align 1
@.str.532 = private unnamed_addr constant [35 x i8] c"  %%%s.addr = alloca ptr, align 8\0A\00", align 1
@.str.533 = private unnamed_addr constant [51 x i8] c"  %%__ap%d = load ptr, ptr %%__args.addr, align 8\0A\00", align 1
@.str.534 = private unnamed_addr constant [54 x i8] c"  %%__ag%d = getelementptr ptr, ptr %%__ap%d, i32 %d\0A\00", align 1
@.str.535 = private unnamed_addr constant [46 x i8] c"  %%__av%d = load ptr, ptr %%__ag%d, align 8\0A\00", align 1
@.str.536 = private unnamed_addr constant [46 x i8] c"  store ptr %%__av%d, ptr %%%s.addr, align 8\0A\00", align 1
@.str.537 = private unnamed_addr constant [10 x i8] c"%%%s.addr\00", align 1
@.str.538 = private unnamed_addr constant [5 x i8] c"null\00", align 1
@.str.539 = private unnamed_addr constant [14 x i8] c"  ret ptr %s\0A\00", align 1
@.str.540 = private unnamed_addr constant [36 x i8] c"define ptr @%s(ptr %%__args.arg) {\0A\00", align 1
@.str.541 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.542 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.543 = private unnamed_addr constant [26 x i8] c"declare ptr @malloc(i64)\0A\00", align 1
@.str.544 = private unnamed_addr constant [48 x i8] c"define private ptr @__cons(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.545 = private unnamed_addr constant [34 x i8] c"  %%c = call ptr @malloc(i64 40)\0A\00", align 1
@.str.546 = private unnamed_addr constant [89 x i8] c"  %%p0 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 0\0A\00", align 1
@.str.547 = private unnamed_addr constant [34 x i8] c"  store i32 3, ptr %%p0, align 8\0A\00", align 1
@.str.548 = private unnamed_addr constant [89 x i8] c"  %%p1 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 1\0A\00", align 1
@.str.549 = private unnamed_addr constant [34 x i8] c"  store i32 0, ptr %%p1, align 4\0A\00", align 1
@.str.550 = private unnamed_addr constant [89 x i8] c"  %%p2 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 2\0A\00", align 1
@.str.551 = private unnamed_addr constant [34 x i8] c"  store i64 0, ptr %%p2, align 8\0A\00", align 1
@.str.552 = private unnamed_addr constant [89 x i8] c"  %%p3 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 3\0A\00", align 1
@.str.553 = private unnamed_addr constant [37 x i8] c"  store ptr null, ptr %%p3, align 8\0A\00", align 1
@.str.554 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 4\0A\00", align 1
@.str.555 = private unnamed_addr constant [36 x i8] c"  store ptr %%a, ptr %%p4, align 8\0A\00", align 1
@.str.556 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 5\0A\00", align 1
@.str.557 = private unnamed_addr constant [36 x i8] c"  store ptr %%b, ptr %%p5, align 8\0A\00", align 1
@.str.558 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.559 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.560 = private unnamed_addr constant [50 x i8] c"define private ptr @__append(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.561 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.562 = private unnamed_addr constant [31 x i8] c"  %%z = icmp eq ptr %%a, null\0A\00", align 1
@.str.563 = private unnamed_addr constant [39 x i8] c"  br i1 %%z, label %%nil, label %%rec\0A\00", align 1
@.str.564 = private unnamed_addr constant [6 x i8] c"nil:\0A\00", align 1
@.str.565 = private unnamed_addr constant [15 x i8] c"  ret ptr %%b\0A\00", align 1
@.str.566 = private unnamed_addr constant [6 x i8] c"rec:\0A\00", align 1
@.str.567 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 4\0A\00", align 1
@.str.568 = private unnamed_addr constant [39 x i8] c"  %%car = load ptr, ptr %%p4, align 8\0A\00", align 1
@.str.569 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 5\0A\00", align 1
@.str.570 = private unnamed_addr constant [39 x i8] c"  %%cdr = load ptr, ptr %%p5, align 8\0A\00", align 1
@.str.571 = private unnamed_addr constant [51 x i8] c"  %%rest = call ptr @__append(ptr %%cdr, ptr %%b)\0A\00", align 1
@.str.572 = private unnamed_addr constant [49 x i8] c"  %%c = call ptr @__cons(ptr %%car, ptr %%rest)\0A\00", align 1
@.str.573 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.574 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.575 = private unnamed_addr constant [31 x i8] c"declare ptr @nucleus_gensym()\0A\00", align 1
@.str.576 = private unnamed_addr constant [30 x i8] c"; ModuleID = '<defmacro %s>'\0A\00", align 1
@.str.577 = private unnamed_addr constant [40 x i8] c"target triple = \22x86_64-pc-linux-gnu\22\0A\0A\00", align 1
@.str.578 = private unnamed_addr constant [54 x i8] c"@.str.%d = private unnamed_addr constant [%d x i8] c\22\00", align 1
@.str.579 = private unnamed_addr constant [6 x i8] c"\5C%02X\00", align 1
@.str.580 = private unnamed_addr constant [15 x i8] c"\5C00\22, align 1\0A\00", align 1
@.str.581 = private unnamed_addr constant [3 x i8] c"rb\00", align 1
@.str.582 = private unnamed_addr constant [6 x i8] c"fseek\00", align 1
@.str.583 = private unnamed_addr constant [6 x i8] c"ftell\00", align 1
@.str.584 = private unnamed_addr constant [7 x i8] c"malloc\00", align 1
@.str.585 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.586 = private unnamed_addr constant [7 x i8] c"defvar\00", align 1
@.str.587 = private unnamed_addr constant [10 x i8] c"defstruct\00", align 1
@.str.588 = private unnamed_addr constant [7 x i8] c"extern\00", align 1
@.str.589 = private unnamed_addr constant [8 x i8] c"declare\00", align 1
@.str.590 = private unnamed_addr constant [4 x i8] c"let\00", align 1
@.str.591 = private unnamed_addr constant [13 x i8] c"compile-time\00", align 1
@.str.592 = private unnamed_addr constant [3 x i8] c"do\00", align 1
@.str.593 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.594 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.595 = private unnamed_addr constant [49 x i8] c"def-rmacro: expects (def-rmacro \22prefix\22 symbol)\00", align 1
@.str.596 = private unnamed_addr constant [36 x i8] c"def-rmacro: prefix must be a string\00", align 1
@.str.597 = private unnamed_addr constant [41 x i8] c"def-rmacro: wrap symbol must be a symbol\00", align 1
@.str.598 = private unnamed_addr constant [53 x i8] c"top-level form must be a list starting with a symbol\00", align 1
@.str.599 = private unnamed_addr constant [9 x i8] c"defconst\00", align 1
@.str.600 = private unnamed_addr constant [8 x i8] c"defenum\00", align 1
@.str.601 = private unnamed_addr constant [7 x i8] c"defvar\00", align 1
@.str.602 = private unnamed_addr constant [10 x i8] c"defstruct\00", align 1
@.str.603 = private unnamed_addr constant [8 x i8] c"include\00", align 1
@.str.604 = private unnamed_addr constant [7 x i8] c"extern\00", align 1
@.str.605 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.606 = private unnamed_addr constant [13 x i8] c"compile-time\00", align 1
@.str.607 = private unnamed_addr constant [9 x i8] c"defmacro\00", align 1
@.str.608 = private unnamed_addr constant [11 x i8] c"def-rmacro\00", align 1
@.str.609 = private unnamed_addr constant [7 x i8] c"import\00", align 1
@.str.610 = private unnamed_addr constant [8 x i8] c"declare\00", align 1
@.str.611 = private unnamed_addr constant [27 x i8] c"unknown top-level form: %s\00", align 1
@.str.612 = private unnamed_addr constant [2 x i8] c"r\00", align 1
@.str.613 = private unnamed_addr constant [6 x i8] c"%s/%s\00", align 1
@.str.614 = private unnamed_addr constant [7 x i8] c"lib/%s\00", align 1
@.str.615 = private unnamed_addr constant [6 x i8] c"%s/%s\00", align 1
@.str.616 = private unnamed_addr constant [7 x i8] c"%s.nuc\00", align 1
@.str.617 = private unnamed_addr constant [8 x i8] c"%s.nuch\00", align 1
@.str.618 = private unnamed_addr constant [31 x i8] c"import: expected (import name)\00", align 1
@.str.619 = private unnamed_addr constant [30 x i8] c"import: name must be a symbol\00", align 1
@.str.620 = private unnamed_addr constant [25 x i8] c"import: cannot find '%s'\00", align 1
@.str.621 = private unnamed_addr constant [32 x i8] c"import: circular import of '%s'\00", align 1
@.str.622 = private unnamed_addr constant [6 x i8] c".nuch\00", align 1
@.str.623 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.624 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.625 = private unnamed_addr constant [3 x i8] c"i1\00", align 1
@.str.626 = private unnamed_addr constant [6 x i8] c"_Bool\00", align 1
@.str.627 = private unnamed_addr constant [3 x i8] c"i8\00", align 1
@.str.628 = private unnamed_addr constant [7 x i8] c"int8_t\00", align 1
@.str.629 = private unnamed_addr constant [4 x i8] c"i16\00", align 1
@.str.630 = private unnamed_addr constant [8 x i8] c"int16_t\00", align 1
@.str.631 = private unnamed_addr constant [4 x i8] c"i32\00", align 1
@.str.632 = private unnamed_addr constant [8 x i8] c"int32_t\00", align 1
@.str.633 = private unnamed_addr constant [4 x i8] c"int\00", align 1
@.str.634 = private unnamed_addr constant [8 x i8] c"int32_t\00", align 1
@.str.635 = private unnamed_addr constant [4 x i8] c"i64\00", align 1
@.str.636 = private unnamed_addr constant [8 x i8] c"int64_t\00", align 1
@.str.637 = private unnamed_addr constant [4 x i8] c"ui8\00", align 1
@.str.638 = private unnamed_addr constant [8 x i8] c"uint8_t\00", align 1
@.str.639 = private unnamed_addr constant [5 x i8] c"ui16\00", align 1
@.str.640 = private unnamed_addr constant [9 x i8] c"uint16_t\00", align 1
@.str.641 = private unnamed_addr constant [5 x i8] c"ui32\00", align 1
@.str.642 = private unnamed_addr constant [9 x i8] c"uint32_t\00", align 1
@.str.643 = private unnamed_addr constant [5 x i8] c"ui64\00", align 1
@.str.644 = private unnamed_addr constant [9 x i8] c"uint64_t\00", align 1
@.str.645 = private unnamed_addr constant [4 x i8] c"ptr\00", align 1
@.str.646 = private unnamed_addr constant [6 x i8] c"void*\00", align 1
@.str.647 = private unnamed_addr constant [4 x i8] c"%s*\00", align 1
@.str.648 = private unnamed_addr constant [10 x i8] c"struct %s\00", align 1
@.str.649 = private unnamed_addr constant [18 x i8] c"typedef struct {\0A\00", align 1
@.str.650 = private unnamed_addr constant [12 x i8] c"    %s %s;\0A\00", align 1
@.str.651 = private unnamed_addr constant [8 x i8] c"} %s;\0A\0A\00", align 1
@.str.652 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.653 = private unnamed_addr constant [7 x i8] c"%s %s(\00", align 1
@.str.654 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.655 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.656 = private unnamed_addr constant [6 x i8] c"%s %s\00", align 1
@.str.657 = private unnamed_addr constant [9 x i8] c"void* %s\00", align 1
@.str.658 = private unnamed_addr constant [4 x i8] c");\0A\00", align 1
@.str.659 = private unnamed_addr constant [16 x i8] c"#define %s %ld\0A\00", align 1
@.str.660 = private unnamed_addr constant [17 x i8] c"#define %s \22%s\22\0A\00", align 1
@.str.661 = private unnamed_addr constant [11 x i8] c"enum %s {\0A\00", align 1
@.str.662 = private unnamed_addr constant [15 x i8] c"    %s_%s = %d\00", align 1
@.str.663 = private unnamed_addr constant [2 x i8] c",\00", align 1
@.str.664 = private unnamed_addr constant [2 x i8] c"\0A\00", align 1
@.str.665 = private unnamed_addr constant [5 x i8] c"};\0A\0A\00", align 1
@.str.666 = private unnamed_addr constant [14 x i8] c"#pragma once\0A\00", align 1
@.str.667 = private unnamed_addr constant [21 x i8] c"#include <stdint.h>\0A\00", align 1
@.str.668 = private unnamed_addr constant [23 x i8] c"#include <stdbool.h>\0A\0A\00", align 1
@.str.669 = private unnamed_addr constant [53 x i8] c"/* Generated from %s by nucleusc --emit-cheader */\0A\0A\00", align 1
@.str.670 = private unnamed_addr constant [10 x i8] c"defstruct\00", align 1
@.str.671 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.672 = private unnamed_addr constant [9 x i8] c"defconst\00", align 1
@.str.673 = private unnamed_addr constant [8 x i8] c"defenum\00", align 1
@.str.674 = private unnamed_addr constant [12 x i8] c"(defstruct \00", align 1
@.str.675 = private unnamed_addr constant [3 x i8] c")\0A\00", align 1
@.str.676 = private unnamed_addr constant [10 x i8] c"(declare \00", align 1
@.str.677 = private unnamed_addr constant [3 x i8] c" (\00", align 1
@.str.678 = private unnamed_addr constant [4 x i8] c"))\0A\00", align 1
@.str.679 = private unnamed_addr constant [11 x i8] c"(defconst \00", align 1
@.str.680 = private unnamed_addr constant [2 x i8] c" \00", align 1
@.str.681 = private unnamed_addr constant [3 x i8] c")\0A\00", align 1
@.str.682 = private unnamed_addr constant [9 x i8] c"(defenum\00", align 1
@.str.683 = private unnamed_addr constant [3 x i8] c")\0A\00", align 1
@.str.684 = private unnamed_addr constant [2 x i8] c"\0A\00", align 1
@.str.685 = private unnamed_addr constant [23 x i8] c"; .nuch header for %s\0A\00", align 1
@.str.686 = private unnamed_addr constant [10 x i8] c"defstruct\00", align 1
@.str.687 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.688 = private unnamed_addr constant [9 x i8] c"defconst\00", align 1
@.str.689 = private unnamed_addr constant [8 x i8] c"defenum\00", align 1
@.str.690 = private unnamed_addr constant [9 x i8] c"defmacro\00", align 1
@.str.691 = private unnamed_addr constant [53 x i8] c"declare: expected (declare name:rettype (params...))\00", align 1
@.str.692 = private unnamed_addr constant [31 x i8] c"declare: missing :type on '%s'\00", align 1
@.str.693 = private unnamed_addr constant [4 x i8] c"@%s\00", align 1
@.str.694 = private unnamed_addr constant [16 x i8] c"declare %s @%s(\00", align 1
@.str.695 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.696 = private unnamed_addr constant [3 x i8] c"%s\00", align 1
@.str.697 = private unnamed_addr constant [3 x i8] c")\0A\00", align 1
@.str.698 = private unnamed_addr constant [10 x i8] c"defstruct\00", align 1
@.str.699 = private unnamed_addr constant [8 x i8] c"declare\00", align 1
@.str.700 = private unnamed_addr constant [9 x i8] c"defconst\00", align 1
@.str.701 = private unnamed_addr constant [8 x i8] c"defenum\00", align 1
@.str.702 = private unnamed_addr constant [9 x i8] c"defmacro\00", align 1
@.str.703 = private unnamed_addr constant [11 x i8] c"def-rmacro\00", align 1
@.str.704 = private unnamed_addr constant [3 x i8] c"~@\00", align 1
@.str.705 = private unnamed_addr constant [15 x i8] c"unquote-splice\00", align 1
@.str.706 = private unnamed_addr constant [2 x i8] c"~\00", align 1
@.str.707 = private unnamed_addr constant [8 x i8] c"unquote\00", align 1
@.str.708 = private unnamed_addr constant [2 x i8] c"'\00", align 1
@.str.709 = private unnamed_addr constant [6 x i8] c"quote\00", align 1
@.str.710 = private unnamed_addr constant [2 x i8] c"`\00", align 1
@.str.711 = private unnamed_addr constant [11 x i8] c"quasiquote\00", align 1
@.str.712 = private unnamed_addr constant [2 x i8] c"@\00", align 1
@.str.713 = private unnamed_addr constant [6 x i8] c"deref\00", align 1
@.str.714 = private unnamed_addr constant [26 x i8] c"declare ptr @malloc(i64)\0A\00", align 1
@.str.715 = private unnamed_addr constant [40 x i8] c"define ptr @__cons(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.716 = private unnamed_addr constant [34 x i8] c"  %%c = call ptr @malloc(i64 40)\0A\00", align 1
@.str.717 = private unnamed_addr constant [89 x i8] c"  %%p0 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 0\0A\00", align 1
@.str.718 = private unnamed_addr constant [34 x i8] c"  store i32 3, ptr %%p0, align 8\0A\00", align 1
@.str.719 = private unnamed_addr constant [89 x i8] c"  %%p1 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 1\0A\00", align 1
@.str.720 = private unnamed_addr constant [34 x i8] c"  store i32 0, ptr %%p1, align 4\0A\00", align 1
@.str.721 = private unnamed_addr constant [89 x i8] c"  %%p2 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 2\0A\00", align 1
@.str.722 = private unnamed_addr constant [34 x i8] c"  store i64 0, ptr %%p2, align 8\0A\00", align 1
@.str.723 = private unnamed_addr constant [89 x i8] c"  %%p3 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 3\0A\00", align 1
@.str.724 = private unnamed_addr constant [37 x i8] c"  store ptr null, ptr %%p3, align 8\0A\00", align 1
@.str.725 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 4\0A\00", align 1
@.str.726 = private unnamed_addr constant [36 x i8] c"  store ptr %%a, ptr %%p4, align 8\0A\00", align 1
@.str.727 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%c, i32 0, i32 5\0A\00", align 1
@.str.728 = private unnamed_addr constant [36 x i8] c"  store ptr %%b, ptr %%p5, align 8\0A\00", align 1
@.str.729 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.730 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.731 = private unnamed_addr constant [42 x i8] c"define ptr @__append(ptr %%a, ptr %%b) {\0A\00", align 1
@.str.732 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.733 = private unnamed_addr constant [31 x i8] c"  %%z = icmp eq ptr %%a, null\0A\00", align 1
@.str.734 = private unnamed_addr constant [39 x i8] c"  br i1 %%z, label %%nil, label %%rec\0A\00", align 1
@.str.735 = private unnamed_addr constant [6 x i8] c"nil:\0A\00", align 1
@.str.736 = private unnamed_addr constant [15 x i8] c"  ret ptr %%b\0A\00", align 1
@.str.737 = private unnamed_addr constant [6 x i8] c"rec:\0A\00", align 1
@.str.738 = private unnamed_addr constant [89 x i8] c"  %%p4 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 4\0A\00", align 1
@.str.739 = private unnamed_addr constant [39 x i8] c"  %%car = load ptr, ptr %%p4, align 8\0A\00", align 1
@.str.740 = private unnamed_addr constant [89 x i8] c"  %%p5 = getelementptr inbounds { i32, i32, i64, ptr, ptr, ptr }, ptr %%a, i32 0, i32 5\0A\00", align 1
@.str.741 = private unnamed_addr constant [39 x i8] c"  %%cdr = load ptr, ptr %%p5, align 8\0A\00", align 1
@.str.742 = private unnamed_addr constant [51 x i8] c"  %%rest = call ptr @__append(ptr %%cdr, ptr %%b)\0A\00", align 1
@.str.743 = private unnamed_addr constant [49 x i8] c"  %%c = call ptr @__cons(ptr %%car, ptr %%rest)\0A\00", align 1
@.str.744 = private unnamed_addr constant [15 x i8] c"  ret ptr %%c\0A\00", align 1
@.str.745 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.746 = private unnamed_addr constant [19 x i8] c"; ModuleID = '%s'\0A\00", align 1
@.str.747 = private unnamed_addr constant [24 x i8] c"source_filename = \22%s\22\0A\00", align 1
@.str.748 = private unnamed_addr constant [40 x i8] c"target triple = \22x86_64-pc-linux-gnu\22\0A\0A\00", align 1
@.str.749 = private unnamed_addr constant [7 x i8] c"malloc\00", align 1
@.str.750 = private unnamed_addr constant [6 x i8] c"nuc> \00", align 1
@.str.751 = private unnamed_addr constant [6 x i8] c"...> \00", align 1
@.str.752 = private unnamed_addr constant [7 x i8] c"malloc\00", align 1
@.str.753 = private unnamed_addr constant [8 x i8] c"realloc\00", align 1
@.str.754 = private unnamed_addr constant [9 x i8] c"defconst\00", align 1
@.str.755 = private unnamed_addr constant [8 x i8] c"defenum\00", align 1
@.str.756 = private unnamed_addr constant [7 x i8] c"defvar\00", align 1
@.str.757 = private unnamed_addr constant [26 x i8] c"@%s = external global %s\0A\00", align 1
@.str.758 = private unnamed_addr constant [11 x i8] c"  defined\0A\00", align 1
@.str.759 = private unnamed_addr constant [10 x i8] c"defstruct\00", align 1
@.str.760 = private unnamed_addr constant [11 x i8] c"  defined\0A\00", align 1
@.str.761 = private unnamed_addr constant [8 x i8] c"include\00", align 1
@.str.762 = private unnamed_addr constant [7 x i8] c"extern\00", align 1
@.str.763 = private unnamed_addr constant [5 x i8] c"defn\00", align 1
@.str.764 = private unnamed_addr constant [39 x i8] c"  error: cannot redefine '%s' in REPL\0A\00", align 1
@.str.765 = private unnamed_addr constant [16 x i8] c"declare %s @%s(\00", align 1
@.str.766 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.767 = private unnamed_addr constant [3 x i8] c"%s\00", align 1
@.str.768 = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.769 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.770 = private unnamed_addr constant [6 x i8] c"%s...\00", align 1
@.str.771 = private unnamed_addr constant [3 x i8] c")\0A\00", align 1
@.str.772 = private unnamed_addr constant [11 x i8] c"  defined\0A\00", align 1
@.str.773 = private unnamed_addr constant [13 x i8] c"compile-time\00", align 1
@.str.774 = private unnamed_addr constant [9 x i8] c"defmacro\00", align 1
@.str.775 = private unnamed_addr constant [11 x i8] c"  defined\0A\00", align 1
@.str.776 = private unnamed_addr constant [11 x i8] c"def-rmacro\00", align 1
@.str.777 = private unnamed_addr constant [11 x i8] c"  defined\0A\00", align 1
@.str.778 = private unnamed_addr constant [7 x i8] c"import\00", align 1
@.str.779 = private unnamed_addr constant [15 x i8] c"declare %s %s(\00", align 1
@.str.780 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.781 = private unnamed_addr constant [3 x i8] c"%s\00", align 1
@.str.782 = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.783 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.str.784 = private unnamed_addr constant [6 x i8] c"%s...\00", align 1
@.str.785 = private unnamed_addr constant [3 x i8] c")\0A\00", align 1
@.str.786 = private unnamed_addr constant [16 x i8] c"__repl_eval_%ld\00", align 1
@.str.787 = private unnamed_addr constant [12 x i8] c"  ret void\0A\00", align 1
@.str.788 = private unnamed_addr constant [26 x i8] c"  %s = zext i1 %s to i32\0A\00", align 1
@.str.789 = private unnamed_addr constant [26 x i8] c"  %s = sext i8 %s to i32\0A\00", align 1
@.str.790 = private unnamed_addr constant [27 x i8] c"  %s = sext i16 %s to i32\0A\00", align 1
@.str.791 = private unnamed_addr constant [14 x i8] c"  ret i32 %s\0A\00", align 1
@.str.792 = private unnamed_addr constant [14 x i8] c"  ret i64 %s\0A\00", align 1
@.str.793 = private unnamed_addr constant [14 x i8] c"  ret ptr %s\0A\00", align 1
@.str.794 = private unnamed_addr constant [12 x i8] c"  ret void\0A\00", align 1
@.str.795 = private unnamed_addr constant [5 x i8] c"void\00", align 1
@.str.796 = private unnamed_addr constant [4 x i8] c"i32\00", align 1
@.str.797 = private unnamed_addr constant [4 x i8] c"i64\00", align 1
@.str.798 = private unnamed_addr constant [4 x i8] c"ptr\00", align 1
@.str.799 = private unnamed_addr constant [19 x i8] c"define %s @%s() {\0A\00", align 1
@.str.800 = private unnamed_addr constant [8 x i8] c"entry:\0A\00", align 1
@.str.801 = private unnamed_addr constant [4 x i8] c"}\0A\0A\00", align 1
@.str.802 = private unnamed_addr constant [24 x i8] c"  JIT lookup error: %s\0A\00", align 1
@.str.803 = private unnamed_addr constant [6 x i8] c"  %d\0A\00", align 1
@.str.804 = private unnamed_addr constant [7 x i8] c"  %ld\0A\00", align 1
@.str.805 = private unnamed_addr constant [6 x i8] c"  %p\0A\00", align 1
@.str.806 = private unnamed_addr constant [8 x i8] c"  null\0A\00", align 1
@.str.807 = private unnamed_addr constant [23 x i8] c"; ModuleID = '<repl>'\0A\00", align 1
@.str.808 = private unnamed_addr constant [40 x i8] c"target triple = \22x86_64-pc-linux-gnu\22\0A\0A\00", align 1
@.str.809 = private unnamed_addr constant [8 x i8] c"stdio.h\00", align 1
@.str.810 = private unnamed_addr constant [9 x i8] c"stdlib.h\00", align 1
@.str.811 = private unnamed_addr constant [9 x i8] c"string.h\00", align 1
@.str.812 = private unnamed_addr constant [8 x i8] c"ctype.h\00", align 1
@.str.813 = private unnamed_addr constant [9 x i8] c"unistd.h\00", align 1
@.str.814 = private unnamed_addr constant [2 x i8] c"\0A\00", align 1
@.str.815 = private unnamed_addr constant [5 x i8] c"Node\00", align 1
@.str.816 = private unnamed_addr constant [5 x i8] c"kind\00", align 1
@.str.817 = private unnamed_addr constant [5 x i8] c"line\00", align 1
@.str.818 = private unnamed_addr constant [2 x i8] c"i\00", align 1
@.str.819 = private unnamed_addr constant [2 x i8] c"s\00", align 1
@.str.820 = private unnamed_addr constant [4 x i8] c"car\00", align 1
@.str.821 = private unnamed_addr constant [4 x i8] c"cdr\00", align 1
@.str.822 = private unnamed_addr constant [49 x i8] c"%%Node = type { i32, i32, i64, ptr, ptr, ptr }\0A\0A\00", align 1
@.str.823 = private unnamed_addr constant [9 x i8] c"NODE-INT\00", align 1
@.str.824 = private unnamed_addr constant [2 x i8] c"0\00", align 1
@.str.825 = private unnamed_addr constant [9 x i8] c"NODE-STR\00", align 1
@.str.826 = private unnamed_addr constant [2 x i8] c"1\00", align 1
@.str.827 = private unnamed_addr constant [9 x i8] c"NODE-SYM\00", align 1
@.str.828 = private unnamed_addr constant [2 x i8] c"2\00", align 1
@.str.829 = private unnamed_addr constant [10 x i8] c"NODE-CELL\00", align 1
@.str.830 = private unnamed_addr constant [2 x i8] c"3\00", align 1
@.str.831 = private unnamed_addr constant [36 x i8] c"Nucleus REPL (type Ctrl-D to exit)\0A\00", align 1
@.str.832 = private unnamed_addr constant [7 x i8] c"<repl>\00", align 1
@.str.833 = private unnamed_addr constant [2 x i8] c"\0A\00", align 1
@.str.834 = private unnamed_addr constant [21 x i8] c"  error (recovered)\0A\00", align 1
@.str.835 = private unnamed_addr constant [12 x i8] c"--emit-nuch\00", align 1
@.str.836 = private unnamed_addr constant [15 x i8] c"--emit-cheader\00", align 1
@.str.837 = private unnamed_addr constant [3 x i8] c"-i\00", align 1
@.str.838 = private unnamed_addr constant [14 x i8] c"--interactive\00", align 1
@.str.839 = private unnamed_addr constant [3 x i8] c"-I\00", align 1
@.str.840 = private unnamed_addr constant [25 x i8] c"-I requires an argument\0A\00", align 1
@.str.841 = private unnamed_addr constant [18 x i8] c"unknown flag: %s\0A\00", align 1
@.str.842 = private unnamed_addr constant [25 x i8] c"unexpected argument: %s\0A\00", align 1
@.str.843 = private unnamed_addr constant [75 x i8] c"usage: nucleusc [--emit-nuch] [--emit-cheader] [-i] [-I<path>] <file.nuc>\0A\00", align 1

declare i32 @remove(ptr)
declare i32 @rename(ptr, ptr)
declare i32 @renameat(i32, ptr, i32, ptr)
declare i32 @fclose(ptr)
declare ptr @tmpfile()
declare ptr @tmpnam(ptr)
declare ptr @tmpnam_r(ptr)
declare ptr @tempnam(ptr, ptr)
declare i32 @fflush(ptr)
declare i32 @fflush_unlocked(ptr)
declare ptr @fopen(ptr, ptr)
declare ptr @freopen(ptr, ptr, ptr)
declare ptr @fdopen(i32, ptr)
declare ptr @fopencookie(ptr, ptr, ptr)
declare ptr @fmemopen(ptr, i64, ptr)
declare ptr @open_memstream(ptr, ptr)
declare void @setbuf(ptr, ptr)
declare i32 @setvbuf(ptr, ptr, i32, i64)
declare void @setbuffer(ptr, ptr, i64)
declare void @setlinebuf(ptr)
declare i32 @fprintf(ptr, ptr, ...)
declare i32 @printf(ptr, ...)
declare i32 @sprintf(ptr, ptr, ...)
declare i32 @vfprintf(ptr, ptr, ptr)
declare i32 @vprintf(ptr, ptr)
declare i32 @vsprintf(ptr, ptr, ptr)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare i32 @vsnprintf(ptr, i64, ptr, ptr)
declare i32 @vasprintf(ptr, ptr, ptr)
declare i32 @__asprintf(ptr, ptr, ...)
declare i32 @asprintf(ptr, ptr, ...)
declare i32 @vdprintf(i32, ptr, ptr)
declare i32 @dprintf(i32, ptr, ...)
declare i32 @fscanf(ptr, ptr, ...)
declare i32 @scanf(ptr, ...)
declare i32 @sscanf(ptr, ptr, ...)
declare i32 @vfscanf(ptr, ptr, ptr)
declare i32 @vscanf(ptr, ptr)
declare i32 @vsscanf(ptr, ptr, ptr)
declare i32 @fgetc(ptr)
declare i32 @getc(ptr)
declare i32 @getchar()
declare i32 @getc_unlocked(ptr)
declare i32 @getchar_unlocked()
declare i32 @fgetc_unlocked(ptr)
declare i32 @fputc(i32, ptr)
declare i32 @putc(i32, ptr)
declare i32 @putchar(i32)
declare i32 @fputc_unlocked(i32, ptr)
declare i32 @putc_unlocked(i32, ptr)
declare i32 @putchar_unlocked(i32)
declare i32 @getw(ptr)
declare i32 @putw(i32, ptr)
declare ptr @fgets(ptr, i32, ptr)
declare ptr @__getdelim(ptr, ptr, i32, ptr)
declare ptr @getdelim(ptr, ptr, i32, ptr)
declare ptr @getline(ptr, ptr, ptr)
declare i32 @fputs(ptr, ptr)
declare i32 @puts(ptr)
declare i32 @ungetc(i32, ptr)
declare i64 @fread(ptr, i64, i64, ptr)
declare i64 @fwrite(ptr, i64, i64, ptr)
declare i64 @fread_unlocked(ptr, i64, i64, ptr)
declare i64 @fwrite_unlocked(ptr, i64, i64, ptr)
declare i32 @fseek(ptr, i64, i32)
declare i64 @ftell(ptr)
declare void @rewind(ptr)
declare i32 @fseeko(ptr, ptr, i32)
declare ptr @ftello(ptr)
declare i32 @fgetpos(ptr, ptr)
declare i32 @fsetpos(ptr, ptr)
declare void @clearerr(ptr)
declare i32 @feof(ptr)
declare i32 @ferror(ptr)
declare void @clearerr_unlocked(ptr)
declare i32 @feof_unlocked(ptr)
declare i32 @ferror_unlocked(ptr)
declare void @perror(ptr)
declare i32 @fileno(ptr)
declare i32 @fileno_unlocked(ptr)
declare i32 @pclose(ptr)
declare ptr @popen(ptr, ptr)
declare ptr @ctermid(ptr)
declare void @flockfile(ptr)
declare i32 @ftrylockfile(ptr)
declare void @funlockfile(ptr)
declare i32 @__uflow(ptr)
declare i32 @__overflow(ptr, i32)

declare ptr @memcpy(ptr, ptr, i64)
declare ptr @memmove(ptr, ptr, i64)
declare ptr @memccpy(ptr, ptr, i32, i64)
declare ptr @memset(ptr, i32, i64)
declare i32 @memcmp(ptr, ptr, i64)
declare i32 @__memcmpeq(ptr, ptr, i64)
declare ptr @memchr(ptr, i32, i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strncpy(ptr, ptr, i64)
declare ptr @strcat(ptr, ptr)
declare ptr @strncat(ptr, ptr, i64)
declare i32 @strcmp(ptr, ptr)
declare i32 @strncmp(ptr, ptr, i64)
declare i32 @strcoll(ptr, ptr)
declare i64 @strxfrm(ptr, ptr, i64)
declare i32 @strcoll_l(ptr, ptr, ptr)
declare i64 @strxfrm_l(ptr, ptr, i64, ptr)
declare ptr @strdup(ptr)
declare ptr @strndup(ptr, i64)
declare ptr @strchr(ptr, i32)
declare ptr @strrchr(ptr, i32)
declare ptr @strchrnul(ptr, i32)
declare i64 @strcspn(ptr, ptr)
declare i64 @strspn(ptr, ptr)
declare ptr @strpbrk(ptr, ptr)
declare ptr @strstr(ptr, ptr)
declare ptr @strtok(ptr, ptr)
declare ptr @__strtok_r(ptr, ptr, ptr)
declare ptr @strtok_r(ptr, ptr, ptr)
declare ptr @strcasestr(ptr, ptr)
declare ptr @memmem(ptr, i64, ptr, i64)
declare ptr @__mempcpy(ptr, ptr, i64)
declare ptr @mempcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @strnlen(ptr, i64)
declare ptr @strerror(i32)
declare i32 @strerror_r(i32, ptr, i64)
declare ptr @strerror_l(i32, ptr)
declare i32 @bcmp(ptr, ptr, i64)
declare void @bcopy(ptr, ptr, i64)
declare void @bzero(ptr, i64)
declare ptr @index(ptr, i32)
declare ptr @rindex(ptr, i32)
declare i32 @ffs(i32)
declare i32 @ffsl(i64)
declare i32 @strcasecmp(ptr, ptr)
declare i32 @strncasecmp(ptr, ptr, i64)
declare i32 @strcasecmp_l(ptr, ptr, ptr)
declare i32 @strncasecmp_l(ptr, ptr, i64, ptr)
declare void @explicit_bzero(ptr, i64)
declare ptr @strsep(ptr, ptr)
declare ptr @strsignal(i32)
declare ptr @__stpcpy(ptr, ptr)
declare ptr @stpcpy(ptr, ptr)
declare ptr @__stpncpy(ptr, ptr, i64)
declare ptr @stpncpy(ptr, ptr, i64)
declare i64 @strlcpy(ptr, ptr, i64)
declare i64 @strlcat(ptr, ptr, i64)

declare ptr @__ctype_b_loc()
declare ptr @__ctype_tolower_loc()
declare ptr @__ctype_toupper_loc()
declare i32 @isalnum(i32)
declare i32 @isalpha(i32)
declare i32 @iscntrl(i32)
declare i32 @isdigit(i32)
declare i32 @islower(i32)
declare i32 @isgraph(i32)
declare i32 @isprint(i32)
declare i32 @ispunct(i32)
declare i32 @isspace(i32)
declare i32 @isupper(i32)
declare i32 @isxdigit(i32)
declare i32 @tolower(i32)
declare i32 @toupper(i32)
declare i32 @isblank(i32)
declare i32 @isascii(i32)
declare i32 @toascii(i32)
declare i32 @_toupper(i32)
declare i32 @_tolower(i32)
declare i32 @isalnum_l(i32, ptr)
declare i32 @isalpha_l(i32, ptr)
declare i32 @iscntrl_l(i32, ptr)
declare i32 @isdigit_l(i32, ptr)
declare i32 @islower_l(i32, ptr)
declare i32 @isgraph_l(i32, ptr)
declare i32 @isprint_l(i32, ptr)
declare i32 @ispunct_l(i32, ptr)
declare i32 @isspace_l(i32, ptr)
declare i32 @isupper_l(i32, ptr)
declare i32 @isxdigit_l(i32, ptr)
declare i32 @isblank_l(i32, ptr)
declare i32 @__tolower_l(i32, ptr)
declare i32 @tolower_l(i32, ptr)
declare i32 @__toupper_l(i32, ptr)
declare i32 @toupper_l(i32, ptr)

declare i32 @access(ptr, i32)
declare i32 @faccessat(i32, ptr, i32, i32)
declare ptr @lseek(i32, ptr, i32)
declare i32 @close(i32)
declare void @closefrom(i32)
declare i64 @read(i32, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i64 @pread(i32, ptr, i64, ptr)
declare i64 @pwrite(i32, ptr, i64, ptr)
declare i32 @pipe(ptr)
declare i32 @alarm(i32)
declare i32 @sleep(i32)
declare ptr @ualarm(ptr, ptr)
declare i32 @usleep(ptr)
declare i32 @pause()
declare i32 @chown(ptr, ptr, ptr)
declare i32 @fchown(i32, ptr, ptr)
declare i32 @lchown(ptr, ptr, ptr)
declare i32 @fchownat(i32, ptr, ptr, ptr, i32)
declare i32 @chdir(ptr)
declare i32 @fchdir(i32)
declare ptr @getcwd(ptr, i64)
declare ptr @getwd(ptr)
declare i32 @dup(i32)
declare i32 @dup2(i32, i32)
declare i32 @execve(ptr, ptr, ptr)
declare i32 @fexecve(i32, ptr, ptr)
declare i32 @execv(ptr, ptr)
declare i32 @execle(ptr, ptr, ...)
declare i32 @execl(ptr, ptr, ...)
declare i32 @execvp(ptr, ptr)
declare i32 @execlp(ptr, ptr, ...)
declare i32 @nice(i32)
declare void @_exit(i32)
declare i64 @pathconf(ptr, i32)
declare i64 @fpathconf(i32, i32)
declare i64 @sysconf(i32)
declare i64 @confstr(i32, ptr, i64)
declare ptr @getpid()
declare ptr @getppid()
declare ptr @getpgrp()
declare ptr @__getpgid(ptr)
declare ptr @getpgid(ptr)
declare i32 @setpgid(ptr, ptr)
declare i32 @setpgrp()
declare ptr @setsid()
declare ptr @getsid(ptr)
declare ptr @getuid()
declare ptr @geteuid()
declare ptr @getgid()
declare ptr @getegid()
declare i32 @getgroups(i32, ptr)
declare i32 @setuid(ptr)
declare i32 @setreuid(ptr, ptr)
declare i32 @seteuid(ptr)
declare i32 @setgid(ptr)
declare i32 @setregid(ptr, ptr)
declare i32 @setegid(ptr)
declare ptr @fork()
declare ptr @vfork()
declare ptr @ttyname(i32)
declare i32 @ttyname_r(i32, ptr, i64)
declare i32 @isatty(i32)
declare i32 @ttyslot()
declare i32 @link(ptr, ptr)
declare i32 @linkat(i32, ptr, i32, ptr, i32)
declare i32 @symlink(ptr, ptr)
declare i64 @readlink(ptr, ptr, i64)
declare i32 @symlinkat(ptr, i32, ptr)
declare i64 @readlinkat(i32, ptr, ptr, i64)
declare i32 @unlink(ptr)
declare i32 @unlinkat(i32, ptr, i32)
declare i32 @rmdir(ptr)
declare ptr @tcgetpgrp(i32)
declare i32 @tcsetpgrp(i32, ptr)
declare ptr @getlogin()
declare i32 @getlogin_r(ptr, i64)
declare i32 @setlogin(ptr)
declare i32 @getopt(i32, ptr, ptr)
declare i32 @gethostname(ptr, i64)
declare i32 @sethostname(ptr, i64)
declare i32 @sethostid(i64)
declare i32 @getdomainname(ptr, i64)
declare i32 @setdomainname(ptr, i64)
declare i32 @vhangup()
declare i32 @revoke(ptr)
declare i32 @profil(ptr, i64, i64, i32)
declare i32 @acct(ptr)
declare ptr @getusershell()
declare void @endusershell()
declare void @setusershell()
declare i32 @daemon(i32, i32)
declare i32 @chroot(ptr)
declare ptr @getpass(ptr)
declare i32 @fsync(i32)
declare i64 @gethostid()
declare void @sync()
declare i32 @getpagesize()
declare i32 @getdtablesize()
declare i32 @truncate(ptr, ptr)
declare i32 @ftruncate(i32, ptr)
declare i32 @brk(ptr)
declare ptr @sbrk(ptr)
declare i64 @syscall(i64, ...)
declare i32 @lockf(i32, i32, ptr)
declare i32 @fdatasync(i32)
declare ptr @crypt(ptr, ptr)

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
declare i32 @repl_try()
declare void @repl_throw()
@stderr = external global ptr

@stdout = external global ptr

@stdin = external global ptr

@g-arena = global ptr null, align 8

@g-arena-used = global i64 0, align 8

@g-arena-cap = global i64 0, align 8

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

@ty-ui8 = global ptr null, align 8

@ty-ui16 = global ptr null, align 8

@ty-ui32 = global ptr null, align 8

@ty-ui64 = global ptr null, align 8

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

@g-macros = global ptr null, align 8

@g-num-macros = global i32 0, align 4

@g-gensym-id = global i32 0, align 4

@g-rmacros = global ptr null, align 8

@g-num-rmacros = global i32 0, align 4

@g-malloc-decl-done = global i32 0, align 4

@g-emit-nuch = global i32 0, align 4

@g-emit-cheader = global i32 0, align 4

@g-interactive = global i32 0, align 4

@g-repl-id = global i32 0, align 4

@g-repl-preamble = global ptr null, align 8

@g-repl-preamble-bufp = global ptr null, align 8

@g-repl-preamble-sizep = global i64 0, align 8

@g-imported = global ptr null, align 8

@g-importing = global ptr null, align 8

@g-include-paths = global ptr null, align 8

@g-num-include-paths = global i32 0, align 4

declare i64 @__ctype_get_mb_cur_max()
declare ptr @atof(ptr)
declare i32 @atoi(ptr)
declare i64 @atol(ptr)
declare ptr @strtod(ptr, ptr)
declare ptr @strtof(ptr, ptr)
declare i64 @strtol(ptr, ptr, i32)
declare i64 @strtoul(ptr, ptr, i32)
declare i64 @strtoq(ptr, ptr, i32)
declare i64 @strtouq(ptr, ptr, i32)
declare i64 @strtoll(ptr, ptr, i32)
declare i64 @strtoull(ptr, ptr, i32)
declare ptr @l64a(i64)
declare i64 @a64l(ptr)
declare i32 @select(i32, ptr, ptr, ptr, ptr)
declare i32 @pselect(i32, ptr, ptr, ptr, ptr, ptr)
declare i64 @random()
declare void @srandom(i32)
declare ptr @initstate(i32, ptr, i64)
declare ptr @setstate(ptr)
declare i32 @random_r(ptr, ptr)
declare i32 @srandom_r(i32, ptr)
declare i32 @initstate_r(i32, ptr, i64, ptr)
declare i32 @setstate_r(ptr, ptr)
declare i32 @rand()
declare void @srand(i32)
declare i32 @rand_r(ptr)
declare ptr @drand48()
declare ptr @erand48(ptr)
declare i64 @lrand48()
declare i64 @nrand48(ptr)
declare i64 @mrand48()
declare i64 @jrand48(ptr)
declare void @srand48(i64)
declare ptr @seed48(ptr)
declare void @lcong48(ptr)
declare i32 @drand48_r(ptr, ptr)
declare i32 @erand48_r(ptr, ptr, ptr)
declare i32 @lrand48_r(ptr, ptr)
declare i32 @nrand48_r(ptr, ptr, ptr)
declare i32 @mrand48_r(ptr, ptr)
declare i32 @jrand48_r(ptr, ptr, ptr)
declare i32 @srand48_r(i64, ptr)
declare i32 @seed48_r(ptr, ptr)
declare i32 @lcong48_r(ptr, ptr)
declare ptr @arc4random()
declare void @arc4random_buf(ptr, i64)
declare ptr @arc4random_uniform(ptr)
declare ptr @malloc(i64)
declare ptr @calloc(i64, i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @reallocarray(ptr, i64, i64)
declare ptr @alloca(i64)
declare ptr @valloc(i64)
declare i32 @posix_memalign(ptr, i64, i64)
declare ptr @aligned_alloc(i64, i64)
declare void @abort()
declare i32 @atexit(ptr)
declare i32 @at_quick_exit(ptr)
declare i32 @on_exit(ptr, ptr)
declare void @exit(i32)
declare void @quick_exit(i32)
declare void @_Exit(i32)
declare ptr @getenv(ptr)
declare i32 @putenv(ptr)
declare i32 @setenv(ptr, ptr, i32)
declare i32 @unsetenv(ptr)
declare i32 @clearenv()
declare ptr @mktemp(ptr)
declare i32 @mkstemp(ptr)
declare i32 @mkstemps(ptr, i32)
declare ptr @mkdtemp(ptr)
declare i32 @system(ptr)
declare ptr @realpath(ptr, ptr)
declare ptr @bsearch(ptr, ptr, i64, i64, ptr)
declare void @qsort(ptr, i64, i64, ptr)
declare i32 @abs(i32)
declare i64 @labs(i64)
declare ptr @div(i32, i32)
declare ptr @ldiv(i64, i64)
declare ptr @ecvt(ptr, i32, ptr, ptr)
declare ptr @fcvt(ptr, i32, ptr, ptr)
declare ptr @gcvt(ptr, i32, ptr)
declare ptr @qecvt(i64, ptr, i32, ptr, ptr)
declare ptr @qfcvt(i64, ptr, i32, ptr, ptr)
declare ptr @qgcvt(i64, ptr, i32, ptr)
declare i32 @ecvt_r(ptr, i32, ptr, ptr, ptr, i64)
declare i32 @fcvt_r(ptr, i32, ptr, ptr, ptr, i64)
declare i32 @qecvt_r(i64, ptr, i32, ptr, ptr, ptr, i64)
declare i32 @qfcvt_r(i64, ptr, i32, ptr, ptr, ptr, i64)
declare i32 @mblen(ptr, i64)
declare i32 @mbtowc(ptr, ptr, i64)
declare i32 @wctomb(ptr, ptr)
declare i64 @mbstowcs(ptr, ptr, i64)
declare i64 @wcstombs(ptr, ptr, i64)
declare i32 @rpmatch(ptr)
declare i32 @getsubopt(ptr, ptr, ptr)
declare i32 @getloadavg(ptr, i32)

define void @arena-init() {
entry:
  %t0 = sext i32 16777216 to i64
  %t1 = call ptr @malloc(i64 %t0)
  store ptr %t1, ptr @g-arena, align 8
  %t2 = load ptr, ptr @g-arena, align 8
  %t3 = icmp eq ptr %t2, null
  br i1 %t3, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t4 = getelementptr inbounds [13 x i8], ptr @.str.18, i64 0, i64 0
  call void @perror(ptr %t4)
  call void @exit(i32 1)
  br label %cond.end0
cond.end0:
  %t5 = sext i32 0 to i64
  store i64 %t5, ptr @g-arena-used, align 8
  %t6 = sext i32 16777216 to i64
  store i64 %t6, ptr @g-arena-cap, align 8
  ret void
}

define void @arena-grow(i64 %min-size.arg) {
entry:
  %min-size.addr = alloca i64, align 8
  store i64 %min-size.arg, ptr %min-size.addr, align 8
  %new-cap.addr.0 = alloca i64, align 8
  %new-arena.addr.8 = alloca ptr, align 8
  %t1 = load i64, ptr @g-arena-cap, align 8
  store i64 %t1, ptr %new-cap.addr.0, align 8
  br label %while.cond0
while.cond0:
  %t2 = load i64, ptr %new-cap.addr.0, align 8
  %t3 = load i64, ptr %min-size.addr, align 8
  %t4 = icmp slt i64 %t2, %t3
  br i1 %t4, label %while.body0, label %while.end0
while.body0:
  %t5 = load i64, ptr %new-cap.addr.0, align 8
  %t6 = sext i32 2 to i64
  %t7 = mul nsw i64 %t5, %t6
  store i64 %t7, ptr %new-cap.addr.0, align 8
  br label %while.cond0
while.end0:
  %t9 = load i64, ptr %new-cap.addr.0, align 8
  %t10 = call ptr @malloc(i64 %t9)
  store ptr %t10, ptr %new-arena.addr.8, align 8
  %t11 = load ptr, ptr %new-arena.addr.8, align 8
  %t12 = icmp eq ptr %t11, null
  br i1 %t12, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t13 = getelementptr inbounds [11 x i8], ptr @.str.19, i64 0, i64 0
  call void @perror(ptr %t13)
  call void @exit(i32 1)
  br label %cond.end1
cond.end1:
  %t14 = load ptr, ptr %new-arena.addr.8, align 8
  store ptr %t14, ptr @g-arena, align 8
  %t15 = sext i32 0 to i64
  store i64 %t15, ptr @g-arena-used, align 8
  %t16 = load i64, ptr %new-cap.addr.0, align 8
  store i64 %t16, ptr @g-arena-cap, align 8
  ret void
}

define ptr @arena-alloc(i64 %n.arg) {
entry:
  %n.addr = alloca i64, align 8
  store i64 %n.arg, ptr %n.addr, align 8
  %p.addr.11 = alloca ptr, align 8
  %t0 = load i64, ptr %n.addr, align 8
  %t1 = sext i32 7 to i64
  %t2 = add nsw i64 %t0, %t1
  %t3 = sext i32 -8 to i64
  %t4 = and i64 %t2, %t3
  store i64 %t4, ptr %n.addr, align 8
  %t5 = load i64, ptr @g-arena-used, align 8
  %t6 = load i64, ptr %n.addr, align 8
  %t7 = add nsw i64 %t5, %t6
  %t8 = load i64, ptr @g-arena-cap, align 8
  %t9 = icmp sgt i64 %t7, %t8
  br i1 %t9, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t10 = load i64, ptr %n.addr, align 8
  call void @arena-grow(i64 %t10)
  br label %cond.end0
cond.end0:
  %t12 = load ptr, ptr @g-arena, align 8
  %t13 = load i64, ptr @g-arena-used, align 8
  %t14 = getelementptr inbounds i8, ptr %t12, i64 %t13
  store ptr %t14, ptr %p.addr.11, align 8
  %t15 = load i64, ptr @g-arena-used, align 8
  %t16 = load i64, ptr %n.addr, align 8
  %t17 = add nsw i64 %t15, %t16
  store i64 %t17, ptr @g-arena-used, align 8
  %t18 = load ptr, ptr %p.addr.11, align 8
  %t19 = load i64, ptr %n.addr, align 8
  %t20 = call ptr @memset(ptr %t18, i32 0, i64 %t19)
  %t21 = load ptr, ptr %p.addr.11, align 8
  ret ptr %t21
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

define ptr @alloc-node() {
entry:
  %t0 = getelementptr %Node, ptr null, i32 1
  %t1 = ptrtoint ptr %t0 to i64
  %t2 = call ptr @arena-alloc(i64 %t1)
  ret ptr %t2
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

define ptr @alloc-tok() {
entry:
  %t0 = getelementptr %Tok, ptr null, i32 1
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
  %t13 = getelementptr inbounds [8 x i8], ptr @.str.20, i64 0, i64 0
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

define void @die-at(i32 %line.arg, ptr %msg.arg) {
entry:
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %msg.addr = alloca ptr, align 8
  store ptr %msg.arg, ptr %msg.addr, align 8
  %t0 = load ptr, ptr @stderr, align 8
  %t1 = getelementptr inbounds [18 x i8], ptr @.str.21, i64 0, i64 0
  %t2 = load ptr, ptr @g-source-path, align 8
  %t3 = load i32, ptr %line.addr, align 4
  %t4 = load ptr, ptr %msg.addr, align 8
  %t5 = call i32 (ptr, ptr, ...) @fprintf(ptr %t0, ptr %t1, ptr %t2, i32 %t3, ptr %t4)
  %t6 = load i32, ptr @g-interactive, align 4
  %t7 = icmp ne i32 %t6, 0
  br i1 %t7, label %cond.then0.0, label %cond.end0
cond.then0.0:
  call void @repl_throw()
  br label %cond.end0
cond.end0:
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
  %t12 = getelementptr inbounds [28 x i8], ptr @.str.22, i64 0, i64 0
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
  %t35 = getelementptr inbounds [19 x i8], ptr @.str.23, i64 0, i64 0
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
  %t42 = getelementptr inbounds [24 x i8], ptr @.str.24, i64 0, i64 0
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
  store i32 4, ptr %t54, align 4
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
  %t61 = getelementptr inbounds [25 x i8], ptr @.str.25, i64 0, i64 0
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
  store i32 3, ptr %t73, align 4
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
  store i32 5, ptr %t85, align 4
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
  %best-idx.addr.36 = alloca i32, align 4
  %best-len.addr.37 = alloca i32, align 4
  %ri.addr.38 = alloca i32, align 4
  %rm.addr.42 = alloca ptr, align 8
  %plen.addr.47 = alloca i32, align 4
  %match.addr.51 = alloca i32, align 4
  %j.addr.52 = alloca i32, align 4
  %and.val7 = alloca i1, align 1
  %rm.addr.84 = alloca ptr, align 8
  %k.addr.89 = alloca i32, align 4
  %tq.addr.96 = alloca ptr, align 8
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
  store i32 6, ptr %t9, align 4
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
  store i32 -1, ptr %best-idx.addr.36, align 4
  store i32 0, ptr %best-len.addr.37, align 4
  store i32 0, ptr %ri.addr.38, align 4
  br label %while.cond3
while.cond3:
  %t39 = load i32, ptr %ri.addr.38, align 4
  %t40 = load i32, ptr @g-num-rmacros, align 4
  %t41 = icmp slt i32 %t39, %t40
  br i1 %t41, label %while.body3, label %while.end3
while.body3:
  %t43 = load ptr, ptr @g-rmacros, align 8
  %t44 = load i32, ptr %ri.addr.38, align 4
  %t45 = sext i32 %t44 to i64
  %t46 = getelementptr inbounds %RMacro, ptr %t43, i64 %t45
  store ptr %t46, ptr %rm.addr.42, align 8
  %t48 = load ptr, ptr %rm.addr.42, align 8
  %t49 = getelementptr inbounds %RMacro, ptr %t48, i32 0, i32 1
  %t50 = load i32, ptr %t49, align 4
  store i32 %t50, ptr %plen.addr.47, align 4
  store i32 1, ptr %match.addr.51, align 4
  store i32 0, ptr %j.addr.52, align 4
  br label %while.cond4
while.cond4:
  %t53 = load i32, ptr %j.addr.52, align 4
  %t54 = load i32, ptr %plen.addr.47, align 4
  %t55 = icmp slt i32 %t53, %t54
  br i1 %t55, label %while.body4, label %while.end4
while.body4:
  %t56 = load ptr, ptr @g-src, align 8
  %t57 = load i64, ptr @g-pos, align 8
  %t58 = load i32, ptr %j.addr.52, align 4
  %t59 = sext i32 %t58 to i64
  %t60 = add nsw i64 %t57, %t59
  %t61 = call i32 @char-at(ptr %t56, i64 %t60)
  %t62 = load ptr, ptr %rm.addr.42, align 8
  %t63 = getelementptr inbounds %RMacro, ptr %t62, i32 0, i32 0
  %t64 = load ptr, ptr %t63, align 8
  %t65 = load i32, ptr %j.addr.52, align 4
  %t66 = sext i32 %t65 to i64
  %t67 = call i32 @char-at(ptr %t64, i64 %t66)
  %t68 = icmp ne i32 %t61, %t67
  br i1 %t68, label %cond.then5.0, label %cond.end5
cond.then5.0:
  store i32 0, ptr %match.addr.51, align 4
  %t69 = load i32, ptr %plen.addr.47, align 4
  store i32 %t69, ptr %j.addr.52, align 4
  br label %cond.end5
cond.end5:
  %t70 = load i32, ptr %j.addr.52, align 4
  %t71 = add nsw i32 %t70, 1
  store i32 %t71, ptr %j.addr.52, align 4
  br label %while.cond4
while.end4:
  %t72 = load i32, ptr %match.addr.51, align 4
  %t73 = icmp ne i32 %t72, 0
  store i1 %t73, ptr %and.val7, align 1
  br i1 %t73, label %and.rhs7, label %and.end7
and.rhs7:
  %t74 = load i32, ptr %plen.addr.47, align 4
  %t75 = load i32, ptr %best-len.addr.37, align 4
  %t76 = icmp sgt i32 %t74, %t75
  store i1 %t76, ptr %and.val7, align 1
  br label %and.end7
and.end7:
  %t77 = load i1, ptr %and.val7, align 1
  br i1 %t77, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t78 = load i32, ptr %ri.addr.38, align 4
  store i32 %t78, ptr %best-idx.addr.36, align 4
  %t79 = load i32, ptr %plen.addr.47, align 4
  store i32 %t79, ptr %best-len.addr.37, align 4
  br label %cond.end6
cond.end6:
  %t80 = load i32, ptr %ri.addr.38, align 4
  %t81 = add nsw i32 %t80, 1
  store i32 %t81, ptr %ri.addr.38, align 4
  br label %while.cond3
while.end3:
  %t82 = load i32, ptr %best-idx.addr.36, align 4
  %t83 = icmp sge i32 %t82, 0
  br i1 %t83, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t85 = load ptr, ptr @g-rmacros, align 8
  %t86 = load i32, ptr %best-idx.addr.36, align 4
  %t87 = sext i32 %t86 to i64
  %t88 = getelementptr inbounds %RMacro, ptr %t85, i64 %t87
  store ptr %t88, ptr %rm.addr.84, align 8
  store i32 0, ptr %k.addr.89, align 4
  br label %while.cond9
while.cond9:
  %t90 = load i32, ptr %k.addr.89, align 4
  %t91 = load i32, ptr %best-len.addr.37, align 4
  %t92 = icmp slt i32 %t90, %t91
  br i1 %t92, label %while.body9, label %while.end9
while.body9:
  %t93 = call i32 @next-char()
  %t94 = load i32, ptr %k.addr.89, align 4
  %t95 = add nsw i32 %t94, 1
  store i32 %t95, ptr %k.addr.89, align 4
  br label %while.cond9
while.end9:
  %t97 = call ptr @alloc-tok()
  store ptr %t97, ptr %tq.addr.96, align 8
  %t98 = load ptr, ptr %tq.addr.96, align 8
  %t99 = getelementptr inbounds %Tok, ptr %t98, i32 0, i32 0
  store i32 2, ptr %t99, align 4
  %t100 = load ptr, ptr %tq.addr.96, align 8
  %t101 = load i32, ptr %line.addr.2, align 4
  %t102 = getelementptr inbounds %Tok, ptr %t100, i32 0, i32 1
  store i32 %t101, ptr %t102, align 4
  %t103 = load ptr, ptr %tq.addr.96, align 8
  %t104 = load ptr, ptr %rm.addr.84, align 8
  %t105 = getelementptr inbounds %RMacro, ptr %t104, i32 0, i32 2
  %t106 = load ptr, ptr %t105, align 8
  %t107 = getelementptr inbounds %Tok, ptr %t103, i32 0, i32 3
  store ptr %t106, ptr %t107, align 8
  %t108 = load ptr, ptr %tq.addr.96, align 8
  ret ptr %t108
cond.end8:
  %t109 = load i32, ptr %c.addr.0, align 4
  %t110 = icmp eq i32 %t109, 34
  br i1 %t110, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t111 = call i32 @next-char()
  %t112 = load i32, ptr %line.addr.2, align 4
  %t113 = call ptr @lex-string(i32 %t112)
  ret ptr %t113
cond.end10:
  %t114 = call ptr @lex-atom()
  ret ptr %t114
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
  %quoted.addr.22 = alloca ptr, align 8
  %sym.addr.24 = alloca ptr, align 8
  %n.addr.52 = alloca ptr, align 8
  %n.addr.71 = alloca ptr, align 8
  %n.addr.90 = alloca ptr, align 8
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
  %t17 = getelementptr inbounds [13 x i8], ptr @.str.26, i64 0, i64 0
  call void @die-at(i32 %t16, ptr %t17)
  br label %cond.end1
cond.end1:
  %t18 = load ptr, ptr %t.addr.0, align 8
  %t19 = getelementptr inbounds %Tok, ptr %t18, i32 0, i32 0
  %t20 = load i32, ptr %t19, align 4
  %t21 = icmp eq i32 %t20, 2
  br i1 %t21, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t23 = call ptr @read-form()
  store ptr %t23, ptr %quoted.addr.22, align 8
  %t25 = call ptr @alloc-node()
  store ptr %t25, ptr %sym.addr.24, align 8
  %t26 = load ptr, ptr %sym.addr.24, align 8
  %t27 = getelementptr inbounds %Node, ptr %t26, i32 0, i32 0
  store i32 2, ptr %t27, align 4
  %t28 = load ptr, ptr %sym.addr.24, align 8
  %t29 = load ptr, ptr %t.addr.0, align 8
  %t30 = getelementptr inbounds %Tok, ptr %t29, i32 0, i32 1
  %t31 = load i32, ptr %t30, align 4
  %t32 = getelementptr inbounds %Node, ptr %t28, i32 0, i32 1
  store i32 %t31, ptr %t32, align 4
  %t33 = load ptr, ptr %sym.addr.24, align 8
  %t34 = load ptr, ptr %t.addr.0, align 8
  %t35 = getelementptr inbounds %Tok, ptr %t34, i32 0, i32 3
  %t36 = load ptr, ptr %t35, align 8
  %t37 = getelementptr inbounds %Node, ptr %t33, i32 0, i32 3
  store ptr %t36, ptr %t37, align 8
  %t38 = load ptr, ptr %sym.addr.24, align 8
  %t39 = load ptr, ptr %quoted.addr.22, align 8
  %t40 = load ptr, ptr %t.addr.0, align 8
  %t41 = getelementptr inbounds %Tok, ptr %t40, i32 0, i32 1
  %t42 = load i32, ptr %t41, align 4
  %t43 = call ptr @make-cell(ptr %t39, ptr null, i32 %t42)
  %t44 = load ptr, ptr %t.addr.0, align 8
  %t45 = getelementptr inbounds %Tok, ptr %t44, i32 0, i32 1
  %t46 = load i32, ptr %t45, align 4
  %t47 = call ptr @make-cell(ptr %t38, ptr %t43, i32 %t46)
  ret ptr %t47
cond.end2:
  %t48 = load ptr, ptr %t.addr.0, align 8
  %t49 = getelementptr inbounds %Tok, ptr %t48, i32 0, i32 0
  %t50 = load i32, ptr %t49, align 4
  %t51 = icmp eq i32 %t50, 3
  br i1 %t51, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t53 = call ptr @alloc-node()
  store ptr %t53, ptr %n.addr.52, align 8
  %t54 = load ptr, ptr %n.addr.52, align 8
  %t55 = getelementptr inbounds %Node, ptr %t54, i32 0, i32 0
  store i32 0, ptr %t55, align 4
  %t56 = load ptr, ptr %n.addr.52, align 8
  %t57 = load ptr, ptr %t.addr.0, align 8
  %t58 = getelementptr inbounds %Tok, ptr %t57, i32 0, i32 1
  %t59 = load i32, ptr %t58, align 4
  %t60 = getelementptr inbounds %Node, ptr %t56, i32 0, i32 1
  store i32 %t59, ptr %t60, align 4
  %t61 = load ptr, ptr %n.addr.52, align 8
  %t62 = load ptr, ptr %t.addr.0, align 8
  %t63 = getelementptr inbounds %Tok, ptr %t62, i32 0, i32 2
  %t64 = load i64, ptr %t63, align 8
  %t65 = getelementptr inbounds %Node, ptr %t61, i32 0, i32 2
  store i64 %t64, ptr %t65, align 8
  %t66 = load ptr, ptr %n.addr.52, align 8
  ret ptr %t66
cond.end3:
  %t67 = load ptr, ptr %t.addr.0, align 8
  %t68 = getelementptr inbounds %Tok, ptr %t67, i32 0, i32 0
  %t69 = load i32, ptr %t68, align 4
  %t70 = icmp eq i32 %t69, 4
  br i1 %t70, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t72 = call ptr @alloc-node()
  store ptr %t72, ptr %n.addr.71, align 8
  %t73 = load ptr, ptr %n.addr.71, align 8
  %t74 = getelementptr inbounds %Node, ptr %t73, i32 0, i32 0
  store i32 1, ptr %t74, align 4
  %t75 = load ptr, ptr %n.addr.71, align 8
  %t76 = load ptr, ptr %t.addr.0, align 8
  %t77 = getelementptr inbounds %Tok, ptr %t76, i32 0, i32 1
  %t78 = load i32, ptr %t77, align 4
  %t79 = getelementptr inbounds %Node, ptr %t75, i32 0, i32 1
  store i32 %t78, ptr %t79, align 4
  %t80 = load ptr, ptr %n.addr.71, align 8
  %t81 = load ptr, ptr %t.addr.0, align 8
  %t82 = getelementptr inbounds %Tok, ptr %t81, i32 0, i32 3
  %t83 = load ptr, ptr %t82, align 8
  %t84 = getelementptr inbounds %Node, ptr %t80, i32 0, i32 3
  store ptr %t83, ptr %t84, align 8
  %t85 = load ptr, ptr %n.addr.71, align 8
  ret ptr %t85
cond.end4:
  %t86 = load ptr, ptr %t.addr.0, align 8
  %t87 = getelementptr inbounds %Tok, ptr %t86, i32 0, i32 0
  %t88 = load i32, ptr %t87, align 4
  %t89 = icmp eq i32 %t88, 5
  br i1 %t89, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t91 = call ptr @alloc-node()
  store ptr %t91, ptr %n.addr.90, align 8
  %t92 = load ptr, ptr %n.addr.90, align 8
  %t93 = getelementptr inbounds %Node, ptr %t92, i32 0, i32 0
  store i32 2, ptr %t93, align 4
  %t94 = load ptr, ptr %n.addr.90, align 8
  %t95 = load ptr, ptr %t.addr.0, align 8
  %t96 = getelementptr inbounds %Tok, ptr %t95, i32 0, i32 1
  %t97 = load i32, ptr %t96, align 4
  %t98 = getelementptr inbounds %Node, ptr %t94, i32 0, i32 1
  store i32 %t97, ptr %t98, align 4
  %t99 = load ptr, ptr %n.addr.90, align 8
  %t100 = load ptr, ptr %t.addr.0, align 8
  %t101 = getelementptr inbounds %Tok, ptr %t100, i32 0, i32 3
  %t102 = load ptr, ptr %t101, align 8
  %t103 = getelementptr inbounds %Node, ptr %t99, i32 0, i32 3
  store ptr %t102, ptr %t103, align 8
  %t104 = load ptr, ptr %n.addr.90, align 8
  ret ptr %t104
cond.end5:
  %t105 = load ptr, ptr %t.addr.0, align 8
  %t106 = getelementptr inbounds %Tok, ptr %t105, i32 0, i32 1
  %t107 = load i32, ptr %t106, align 4
  %t108 = getelementptr inbounds [24 x i8], ptr @.str.27, i64 0, i64 0
  call void @die-at(i32 %t107, ptr %t108)
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
  %t8 = icmp eq i32 %t7, 6
  br i1 %t8, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t9 = load i32, ptr %line.addr, align 4
  %t10 = getelementptr inbounds [18 x i8], ptr @.str.28, i64 0, i64 0
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
  %t5 = icmp ne i32 %t4, 6
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

define void @print-node(ptr %n.arg) {
entry:
  %n.addr = alloca ptr, align 8
  store ptr %n.arg, ptr %n.addr, align 8
  %nn.addr.4 = alloca ptr, align 8
  %s.addr.30 = alloca ptr, align 8
  %i.addr.34 = alloca i64, align 8
  %len.addr.36 = alloca i64, align 8
  %c.addr.42 = alloca i32, align 4
  %cur.addr.96 = alloca ptr, align 8
  %first.addr.98 = alloca i32, align 4
  %and.val8 = alloca i1, align 1
  %t0 = load ptr, ptr %n.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t2 = getelementptr inbounds [3 x i8], ptr @.str.29, i64 0, i64 0
  %t3 = call i32 (ptr, ...) @printf(ptr %t2)
  ret void
cond.end0:
  %t5 = load ptr, ptr %n.addr, align 8
  store ptr %t5, ptr %nn.addr.4, align 8
  %t6 = load ptr, ptr %nn.addr.4, align 8
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 0
  %t8 = load i32, ptr %t7, align 4
  %t9 = icmp eq i32 %t8, 0
  br i1 %t9, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t10 = getelementptr inbounds [4 x i8], ptr @.str.30, i64 0, i64 0
  %t11 = load ptr, ptr %nn.addr.4, align 8
  %t12 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 2
  %t13 = load i64, ptr %t12, align 8
  %t14 = call i32 (ptr, ...) @printf(ptr %t10, i64 %t13)
  ret void
cond.end1:
  %t15 = load ptr, ptr %nn.addr.4, align 8
  %t16 = getelementptr inbounds %Node, ptr %t15, i32 0, i32 0
  %t17 = load i32, ptr %t16, align 4
  %t18 = icmp eq i32 %t17, 2
  br i1 %t18, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t19 = load ptr, ptr %nn.addr.4, align 8
  %t20 = getelementptr inbounds %Node, ptr %t19, i32 0, i32 3
  %t21 = load ptr, ptr %t20, align 8
  %t22 = load ptr, ptr @stdout, align 8
  %t23 = call i32 @fputs(ptr %t21, ptr %t22)
  ret void
cond.end2:
  %t24 = load ptr, ptr %nn.addr.4, align 8
  %t25 = getelementptr inbounds %Node, ptr %t24, i32 0, i32 0
  %t26 = load i32, ptr %t25, align 4
  %t27 = icmp eq i32 %t26, 1
  br i1 %t27, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t28 = load ptr, ptr @stdout, align 8
  %t29 = call i32 @fputc(i32 34, ptr %t28)
  %t31 = load ptr, ptr %nn.addr.4, align 8
  %t32 = getelementptr inbounds %Node, ptr %t31, i32 0, i32 3
  %t33 = load ptr, ptr %t32, align 8
  store ptr %t33, ptr %s.addr.30, align 8
  %t35 = sext i32 0 to i64
  store i64 %t35, ptr %i.addr.34, align 8
  %t37 = load ptr, ptr %s.addr.30, align 8
  %t38 = call i64 @strlen(ptr %t37)
  store i64 %t38, ptr %len.addr.36, align 8
  br label %while.cond4
while.cond4:
  %t39 = load i64, ptr %i.addr.34, align 8
  %t40 = load i64, ptr %len.addr.36, align 8
  %t41 = icmp slt i64 %t39, %t40
  br i1 %t41, label %while.body4, label %while.end4
while.body4:
  %t43 = load ptr, ptr %s.addr.30, align 8
  %t44 = load i64, ptr %i.addr.34, align 8
  %t45 = call i32 @char-at(ptr %t43, i64 %t44)
  store i32 %t45, ptr %c.addr.42, align 4
  %t46 = load i32, ptr %c.addr.42, align 4
  %t47 = icmp eq i32 %t46, 10
  br i1 %t47, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t48 = load ptr, ptr @stdout, align 8
  %t49 = call i32 @fputc(i32 92, ptr %t48)
  %t50 = load ptr, ptr @stdout, align 8
  %t51 = call i32 @fputc(i32 110, ptr %t50)
  br label %cond.end5
cond.test5.1:
  %t52 = load i32, ptr %c.addr.42, align 4
  %t53 = icmp eq i32 %t52, 9
  br i1 %t53, label %cond.then5.1, label %cond.test5.2
cond.then5.1:
  %t54 = load ptr, ptr @stdout, align 8
  %t55 = call i32 @fputc(i32 92, ptr %t54)
  %t56 = load ptr, ptr @stdout, align 8
  %t57 = call i32 @fputc(i32 116, ptr %t56)
  br label %cond.end5
cond.test5.2:
  %t58 = load i32, ptr %c.addr.42, align 4
  %t59 = icmp eq i32 %t58, 13
  br i1 %t59, label %cond.then5.2, label %cond.test5.3
cond.then5.2:
  %t60 = load ptr, ptr @stdout, align 8
  %t61 = call i32 @fputc(i32 92, ptr %t60)
  %t62 = load ptr, ptr @stdout, align 8
  %t63 = call i32 @fputc(i32 114, ptr %t62)
  br label %cond.end5
cond.test5.3:
  %t64 = load i32, ptr %c.addr.42, align 4
  %t65 = icmp eq i32 %t64, 92
  br i1 %t65, label %cond.then5.3, label %cond.test5.4
cond.then5.3:
  %t66 = load ptr, ptr @stdout, align 8
  %t67 = call i32 @fputc(i32 92, ptr %t66)
  %t68 = load ptr, ptr @stdout, align 8
  %t69 = call i32 @fputc(i32 92, ptr %t68)
  br label %cond.end5
cond.test5.4:
  %t70 = load i32, ptr %c.addr.42, align 4
  %t71 = icmp eq i32 %t70, 34
  br i1 %t71, label %cond.then5.4, label %cond.test5.5
cond.then5.4:
  %t72 = load ptr, ptr @stdout, align 8
  %t73 = call i32 @fputc(i32 92, ptr %t72)
  %t74 = load ptr, ptr @stdout, align 8
  %t75 = call i32 @fputc(i32 34, ptr %t74)
  br label %cond.end5
cond.test5.5:
  %t76 = load i32, ptr %c.addr.42, align 4
  %t77 = icmp eq i32 %t76, 0
  br i1 %t77, label %cond.then5.5, label %cond.test5.6
cond.then5.5:
  %t78 = load ptr, ptr @stdout, align 8
  %t79 = call i32 @fputc(i32 92, ptr %t78)
  %t80 = load ptr, ptr @stdout, align 8
  %t81 = call i32 @fputc(i32 48, ptr %t80)
  br label %cond.end5
cond.test5.6:
  br i1 1, label %cond.then5.6, label %cond.end5
cond.then5.6:
  %t82 = load i32, ptr %c.addr.42, align 4
  %t83 = load ptr, ptr @stdout, align 8
  %t84 = call i32 @fputc(i32 %t82, ptr %t83)
  br label %cond.end5
cond.end5:
  %t85 = load i64, ptr %i.addr.34, align 8
  %t86 = sext i32 1 to i64
  %t87 = add nsw i64 %t85, %t86
  store i64 %t87, ptr %i.addr.34, align 8
  br label %while.cond4
while.end4:
  %t88 = load ptr, ptr @stdout, align 8
  %t89 = call i32 @fputc(i32 34, ptr %t88)
  ret void
cond.end3:
  %t90 = load ptr, ptr %nn.addr.4, align 8
  %t91 = getelementptr inbounds %Node, ptr %t90, i32 0, i32 0
  %t92 = load i32, ptr %t91, align 4
  %t93 = icmp eq i32 %t92, 3
  br i1 %t93, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t94 = load ptr, ptr @stdout, align 8
  %t95 = call i32 @fputc(i32 40, ptr %t94)
  %t97 = load ptr, ptr %n.addr, align 8
  store ptr %t97, ptr %cur.addr.96, align 8
  store i32 1, ptr %first.addr.98, align 4
  br label %while.cond7
while.cond7:
  %t99 = load ptr, ptr %cur.addr.96, align 8
  %t100 = icmp ne ptr %t99, null
  store i1 %t100, ptr %and.val8, align 1
  br i1 %t100, label %and.rhs8, label %and.end8
and.rhs8:
  %t101 = load ptr, ptr %cur.addr.96, align 8
  %t102 = getelementptr inbounds %Node, ptr %t101, i32 0, i32 0
  %t103 = load i32, ptr %t102, align 4
  %t104 = icmp eq i32 %t103, 3
  store i1 %t104, ptr %and.val8, align 1
  br label %and.end8
and.end8:
  %t105 = load i1, ptr %and.val8, align 1
  br i1 %t105, label %while.body7, label %while.end7
while.body7:
  %t106 = load i32, ptr %first.addr.98, align 4
  %t107 = icmp eq i32 %t106, 0
  br i1 %t107, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t108 = load ptr, ptr @stdout, align 8
  %t109 = call i32 @fputc(i32 32, ptr %t108)
  br label %cond.end9
cond.end9:
  store i32 0, ptr %first.addr.98, align 4
  %t110 = load ptr, ptr %cur.addr.96, align 8
  %t111 = getelementptr inbounds %Node, ptr %t110, i32 0, i32 4
  %t112 = load ptr, ptr %t111, align 8
  call void @print-node(ptr %t112)
  %t113 = load ptr, ptr %cur.addr.96, align 8
  %t114 = getelementptr inbounds %Node, ptr %t113, i32 0, i32 5
  %t115 = load ptr, ptr %t114, align 8
  store ptr %t115, ptr %cur.addr.96, align 8
  br label %while.cond7
while.end7:
  %t116 = load ptr, ptr @stdout, align 8
  %t117 = call i32 @fputc(i32 41, ptr %t116)
  ret void
cond.end6:
  ret void
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
  store ptr %t6, ptr @ty-ui8, align 8
  %t7 = call ptr @make-type(i32 7)
  store ptr %t7, ptr @ty-ui16, align 8
  %t8 = call ptr @make-type(i32 8)
  store ptr %t8, ptr @ty-ui32, align 8
  %t9 = call ptr @make-type(i32 9)
  store ptr %t9, ptr @ty-ui64, align 8
  %t10 = call ptr @make-type(i32 10)
  store ptr %t10, ptr @ty-ptr, align 8
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
  %t36 = getelementptr inbounds [3 x i8], ptr @.str.37, i64 0, i64 0
  ret ptr %t36
cond.end6:
  %t37 = load ptr, ptr %tt.addr.0, align 8
  %t38 = getelementptr inbounds %Type, ptr %t37, i32 0, i32 0
  %t39 = load i32, ptr %t38, align 4
  %t40 = icmp eq i32 %t39, 7
  br i1 %t40, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t41 = getelementptr inbounds [4 x i8], ptr @.str.38, i64 0, i64 0
  ret ptr %t41
cond.end7:
  %t42 = load ptr, ptr %tt.addr.0, align 8
  %t43 = getelementptr inbounds %Type, ptr %t42, i32 0, i32 0
  %t44 = load i32, ptr %t43, align 4
  %t45 = icmp eq i32 %t44, 8
  br i1 %t45, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t46 = getelementptr inbounds [4 x i8], ptr @.str.39, i64 0, i64 0
  ret ptr %t46
cond.end8:
  %t47 = load ptr, ptr %tt.addr.0, align 8
  %t48 = getelementptr inbounds %Type, ptr %t47, i32 0, i32 0
  %t49 = load i32, ptr %t48, align 4
  %t50 = icmp eq i32 %t49, 9
  br i1 %t50, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t51 = getelementptr inbounds [4 x i8], ptr @.str.40, i64 0, i64 0
  ret ptr %t51
cond.end9:
  %t52 = load ptr, ptr %tt.addr.0, align 8
  %t53 = getelementptr inbounds %Type, ptr %t52, i32 0, i32 0
  %t54 = load i32, ptr %t53, align 4
  %t55 = icmp eq i32 %t54, 10
  br i1 %t55, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t56 = getelementptr inbounds [4 x i8], ptr @.str.41, i64 0, i64 0
  ret ptr %t56
cond.end10:
  %t57 = load ptr, ptr %tt.addr.0, align 8
  %t58 = getelementptr inbounds %Type, ptr %t57, i32 0, i32 0
  %t59 = load i32, ptr %t58, align 4
  %t60 = icmp eq i32 %t59, 11
  br i1 %t60, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t61 = getelementptr inbounds [4 x i8], ptr @.str.42, i64 0, i64 0
  ret ptr %t61
cond.end11:
  %t62 = load ptr, ptr %tt.addr.0, align 8
  %t63 = getelementptr inbounds %Type, ptr %t62, i32 0, i32 0
  %t64 = load i32, ptr %t63, align 4
  %t65 = icmp eq i32 %t64, 12
  br i1 %t65, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t66 = getelementptr inbounds [5 x i8], ptr @.str.43, i64 0, i64 0
  %t67 = load ptr, ptr %tt.addr.0, align 8
  %t68 = getelementptr inbounds %Type, ptr %t67, i32 0, i32 6
  %t69 = load ptr, ptr %t68, align 8
  %t70 = getelementptr inbounds %StructDef, ptr %t69, i32 0, i32 0
  %t71 = load ptr, ptr %t70, align 8
  %t72 = call ptr @fmt-s(ptr %t66, ptr %t71)
  ret ptr %t72
cond.end12:
  %t73 = getelementptr inbounds [2 x i8], ptr @.str.44, i64 0, i64 0
  ret ptr %t73
}

define ptr @type-to-c(ptr %t.arg) {
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
  %t6 = getelementptr inbounds [5 x i8], ptr @.str.45, i64 0, i64 0
  ret ptr %t6
cond.end0:
  %t7 = load ptr, ptr %tt.addr.0, align 8
  %t8 = getelementptr inbounds %Type, ptr %t7, i32 0, i32 0
  %t9 = load i32, ptr %t8, align 4
  %t10 = icmp eq i32 %t9, 1
  br i1 %t10, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t11 = getelementptr inbounds [6 x i8], ptr @.str.46, i64 0, i64 0
  ret ptr %t11
cond.end1:
  %t12 = load ptr, ptr %tt.addr.0, align 8
  %t13 = getelementptr inbounds %Type, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp eq i32 %t14, 2
  br i1 %t15, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t16 = getelementptr inbounds [7 x i8], ptr @.str.47, i64 0, i64 0
  ret ptr %t16
cond.end2:
  %t17 = load ptr, ptr %tt.addr.0, align 8
  %t18 = getelementptr inbounds %Type, ptr %t17, i32 0, i32 0
  %t19 = load i32, ptr %t18, align 4
  %t20 = icmp eq i32 %t19, 3
  br i1 %t20, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t21 = getelementptr inbounds [8 x i8], ptr @.str.48, i64 0, i64 0
  ret ptr %t21
cond.end3:
  %t22 = load ptr, ptr %tt.addr.0, align 8
  %t23 = getelementptr inbounds %Type, ptr %t22, i32 0, i32 0
  %t24 = load i32, ptr %t23, align 4
  %t25 = icmp eq i32 %t24, 4
  br i1 %t25, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t26 = getelementptr inbounds [8 x i8], ptr @.str.49, i64 0, i64 0
  ret ptr %t26
cond.end4:
  %t27 = load ptr, ptr %tt.addr.0, align 8
  %t28 = getelementptr inbounds %Type, ptr %t27, i32 0, i32 0
  %t29 = load i32, ptr %t28, align 4
  %t30 = icmp eq i32 %t29, 5
  br i1 %t30, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t31 = getelementptr inbounds [8 x i8], ptr @.str.50, i64 0, i64 0
  ret ptr %t31
cond.end5:
  %t32 = load ptr, ptr %tt.addr.0, align 8
  %t33 = getelementptr inbounds %Type, ptr %t32, i32 0, i32 0
  %t34 = load i32, ptr %t33, align 4
  %t35 = icmp eq i32 %t34, 6
  br i1 %t35, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t36 = getelementptr inbounds [8 x i8], ptr @.str.51, i64 0, i64 0
  ret ptr %t36
cond.end6:
  %t37 = load ptr, ptr %tt.addr.0, align 8
  %t38 = getelementptr inbounds %Type, ptr %t37, i32 0, i32 0
  %t39 = load i32, ptr %t38, align 4
  %t40 = icmp eq i32 %t39, 7
  br i1 %t40, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t41 = getelementptr inbounds [9 x i8], ptr @.str.52, i64 0, i64 0
  ret ptr %t41
cond.end7:
  %t42 = load ptr, ptr %tt.addr.0, align 8
  %t43 = getelementptr inbounds %Type, ptr %t42, i32 0, i32 0
  %t44 = load i32, ptr %t43, align 4
  %t45 = icmp eq i32 %t44, 8
  br i1 %t45, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t46 = getelementptr inbounds [9 x i8], ptr @.str.53, i64 0, i64 0
  ret ptr %t46
cond.end8:
  %t47 = load ptr, ptr %tt.addr.0, align 8
  %t48 = getelementptr inbounds %Type, ptr %t47, i32 0, i32 0
  %t49 = load i32, ptr %t48, align 4
  %t50 = icmp eq i32 %t49, 9
  br i1 %t50, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t51 = getelementptr inbounds [9 x i8], ptr @.str.54, i64 0, i64 0
  ret ptr %t51
cond.end9:
  %t52 = load ptr, ptr %tt.addr.0, align 8
  %t53 = getelementptr inbounds %Type, ptr %t52, i32 0, i32 0
  %t54 = load i32, ptr %t53, align 4
  %t55 = icmp eq i32 %t54, 10
  br i1 %t55, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t56 = getelementptr inbounds [6 x i8], ptr @.str.55, i64 0, i64 0
  ret ptr %t56
cond.end10:
  %t57 = load ptr, ptr %tt.addr.0, align 8
  %t58 = getelementptr inbounds %Type, ptr %t57, i32 0, i32 0
  %t59 = load i32, ptr %t58, align 4
  %t60 = icmp eq i32 %t59, 11
  br i1 %t60, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t61 = getelementptr inbounds [6 x i8], ptr @.str.56, i64 0, i64 0
  ret ptr %t61
cond.end11:
  %t62 = load ptr, ptr %tt.addr.0, align 8
  %t63 = getelementptr inbounds %Type, ptr %t62, i32 0, i32 0
  %t64 = load i32, ptr %t63, align 4
  %t65 = icmp eq i32 %t64, 12
  br i1 %t65, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t66 = getelementptr inbounds [10 x i8], ptr @.str.57, i64 0, i64 0
  %t67 = load ptr, ptr %tt.addr.0, align 8
  %t68 = getelementptr inbounds %Type, ptr %t67, i32 0, i32 6
  %t69 = load ptr, ptr %t68, align 8
  %t70 = getelementptr inbounds %StructDef, ptr %t69, i32 0, i32 0
  %t71 = load ptr, ptr %t70, align 8
  %t72 = call ptr @fmt-s(ptr %t66, ptr %t71)
  ret ptr %t72
cond.end12:
  %t73 = getelementptr inbounds [14 x i8], ptr @.str.58, i64 0, i64 0
  ret ptr %t73
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
  ret i32 1
cond.end5:
  %t26 = load ptr, ptr %tt.addr.0, align 8
  %t27 = getelementptr inbounds %Type, ptr %t26, i32 0, i32 0
  %t28 = load i32, ptr %t27, align 4
  %t29 = icmp eq i32 %t28, 7
  br i1 %t29, label %cond.then6.0, label %cond.end6
cond.then6.0:
  ret i32 2
cond.end6:
  %t30 = load ptr, ptr %tt.addr.0, align 8
  %t31 = getelementptr inbounds %Type, ptr %t30, i32 0, i32 0
  %t32 = load i32, ptr %t31, align 4
  %t33 = icmp eq i32 %t32, 8
  br i1 %t33, label %cond.then7.0, label %cond.end7
cond.then7.0:
  ret i32 4
cond.end7:
  %t34 = load ptr, ptr %tt.addr.0, align 8
  %t35 = getelementptr inbounds %Type, ptr %t34, i32 0, i32 0
  %t36 = load i32, ptr %t35, align 4
  %t37 = icmp eq i32 %t36, 9
  br i1 %t37, label %cond.then8.0, label %cond.end8
cond.then8.0:
  ret i32 8
cond.end8:
  %t38 = load ptr, ptr %tt.addr.0, align 8
  %t39 = getelementptr inbounds %Type, ptr %t38, i32 0, i32 0
  %t40 = load i32, ptr %t39, align 4
  %t41 = icmp eq i32 %t40, 10
  br i1 %t41, label %cond.then9.0, label %cond.end9
cond.then9.0:
  ret i32 8
cond.end9:
  %t42 = load ptr, ptr %tt.addr.0, align 8
  %t43 = getelementptr inbounds %Type, ptr %t42, i32 0, i32 0
  %t44 = load i32, ptr %t43, align 4
  %t45 = icmp eq i32 %t44, 12
  br i1 %t45, label %cond.then10.0, label %cond.end10
cond.then10.0:
  ret i32 8
cond.end10:
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
  %t14 = load i32, ptr %k.addr.0, align 4
  %t15 = icmp eq i32 %t14, 6
  br i1 %t15, label %cond.then5.0, label %cond.end5
cond.then5.0:
  ret i32 1
cond.end5:
  %t16 = load i32, ptr %k.addr.0, align 4
  %t17 = icmp eq i32 %t16, 7
  br i1 %t17, label %cond.then6.0, label %cond.end6
cond.then6.0:
  ret i32 1
cond.end6:
  %t18 = load i32, ptr %k.addr.0, align 4
  %t19 = icmp eq i32 %t18, 8
  br i1 %t19, label %cond.then7.0, label %cond.end7
cond.then7.0:
  ret i32 1
cond.end7:
  %t20 = load i32, ptr %k.addr.0, align 4
  %t21 = icmp eq i32 %t20, 9
  br i1 %t21, label %cond.then8.0, label %cond.end8
cond.then8.0:
  ret i32 1
cond.end8:
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
  %t14 = load i32, ptr %k.addr.0, align 4
  %t15 = icmp eq i32 %t14, 6
  br i1 %t15, label %cond.then5.0, label %cond.end5
cond.then5.0:
  ret i32 8
cond.end5:
  %t16 = load i32, ptr %k.addr.0, align 4
  %t17 = icmp eq i32 %t16, 7
  br i1 %t17, label %cond.then6.0, label %cond.end6
cond.then6.0:
  ret i32 16
cond.end6:
  %t18 = load i32, ptr %k.addr.0, align 4
  %t19 = icmp eq i32 %t18, 8
  br i1 %t19, label %cond.then7.0, label %cond.end7
cond.then7.0:
  ret i32 32
cond.end7:
  %t20 = load i32, ptr %k.addr.0, align 4
  %t21 = icmp eq i32 %t20, 9
  br i1 %t21, label %cond.then8.0, label %cond.end8
cond.then8.0:
  ret i32 64
cond.end8:
  ret i32 0
}

define i32 @is-unsigned(ptr %t.arg) {
entry:
  %t.addr = alloca ptr, align 8
  store ptr %t.arg, ptr %t.addr, align 8
  %k.addr.0 = alloca i32, align 4
  %t1 = load ptr, ptr %t.addr, align 8
  %t2 = getelementptr inbounds %Type, ptr %t1, i32 0, i32 0
  %t3 = load i32, ptr %t2, align 4
  store i32 %t3, ptr %k.addr.0, align 4
  %t4 = load i32, ptr %k.addr.0, align 4
  %t5 = icmp eq i32 %t4, 6
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret i32 1
cond.end0:
  %t6 = load i32, ptr %k.addr.0, align 4
  %t7 = icmp eq i32 %t6, 7
  br i1 %t7, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret i32 1
cond.end1:
  %t8 = load i32, ptr %k.addr.0, align 4
  %t9 = icmp eq i32 %t8, 8
  br i1 %t9, label %cond.then2.0, label %cond.end2
cond.then2.0:
  ret i32 1
cond.end2:
  %t10 = load i32, ptr %k.addr.0, align 4
  %t11 = icmp eq i32 %t10, 9
  br i1 %t11, label %cond.then3.0, label %cond.end3
cond.then3.0:
  ret i32 1
cond.end3:
  ret i32 0
}

define ptr @coerce-int-val(ptr %v.arg, ptr %target.arg, i32 %line.arg) {
entry:
  %v.addr = alloca ptr, align 8
  store ptr %v.arg, ptr %v.addr, align 8
  %target.addr = alloca ptr, align 8
  store ptr %target.arg, ptr %target.addr, align 8
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %vv.addr.0 = alloca ptr, align 8
  %src.addr.2 = alloca ptr, align 8
  %sk.addr.6 = alloca i32, align 4
  %dk.addr.10 = alloca i32, align 4
  %and.val2 = alloca i1, align 1
  %sw.addr.25 = alloca i32, align 4
  %dw.addr.28 = alloca i32, align 4
  %tmp.addr.39 = alloca ptr, align 8
  %instr.addr.41 = alloca ptr, align 8
  %t1 = load ptr, ptr %v.addr, align 8
  store ptr %t1, ptr %vv.addr.0, align 8
  %t3 = load ptr, ptr %vv.addr.0, align 8
  %t4 = getelementptr inbounds %Val, ptr %t3, i32 0, i32 0
  %t5 = load ptr, ptr %t4, align 8
  store ptr %t5, ptr %src.addr.2, align 8
  %t7 = load ptr, ptr %src.addr.2, align 8
  %t8 = getelementptr inbounds %Type, ptr %t7, i32 0, i32 0
  %t9 = load i32, ptr %t8, align 4
  store i32 %t9, ptr %sk.addr.6, align 4
  %t11 = load ptr, ptr %target.addr, align 8
  %t12 = getelementptr inbounds %Type, ptr %t11, i32 0, i32 0
  %t13 = load i32, ptr %t12, align 4
  store i32 %t13, ptr %dk.addr.10, align 4
  %t14 = load i32, ptr %sk.addr.6, align 4
  %t15 = load i32, ptr %dk.addr.10, align 4
  %t16 = icmp eq i32 %t14, %t15
  br i1 %t16, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t17 = load ptr, ptr %v.addr, align 8
  ret ptr %t17
cond.end0:
  %t18 = load ptr, ptr %src.addr.2, align 8
  %t19 = call i32 @is-int-type(ptr %t18)
  %t20 = icmp ne i32 %t19, 0
  store i1 %t20, ptr %and.val2, align 1
  br i1 %t20, label %and.rhs2, label %and.end2
and.rhs2:
  %t21 = load ptr, ptr %target.addr, align 8
  %t22 = call i32 @is-int-type(ptr %t21)
  %t23 = icmp ne i32 %t22, 0
  store i1 %t23, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t24 = load i1, ptr %and.val2, align 1
  br i1 %t24, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t26 = load ptr, ptr %src.addr.2, align 8
  %t27 = call i32 @int-width(ptr %t26)
  store i32 %t27, ptr %sw.addr.25, align 4
  %t29 = load ptr, ptr %target.addr, align 8
  %t30 = call i32 @int-width(ptr %t29)
  store i32 %t30, ptr %dw.addr.28, align 4
  %t31 = load i32, ptr %sw.addr.25, align 4
  %t32 = load i32, ptr %dw.addr.28, align 4
  %t33 = icmp eq i32 %t31, %t32
  br i1 %t33, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t34 = load ptr, ptr %target.addr, align 8
  %t35 = load ptr, ptr %vv.addr.0, align 8
  %t36 = getelementptr inbounds %Val, ptr %t35, i32 0, i32 1
  %t37 = load ptr, ptr %t36, align 8
  %t38 = call ptr @alloc-val(ptr %t34, ptr %t37)
  ret ptr %t38
cond.end3:
  %t40 = call ptr @new-tmp()
  store ptr %t40, ptr %tmp.addr.39, align 8
  store ptr null, ptr %instr.addr.41, align 8
  %t42 = load i32, ptr %dw.addr.28, align 4
  %t43 = load i32, ptr %sw.addr.25, align 4
  %t44 = icmp slt i32 %t42, %t43
  br i1 %t44, label %cond.then4.0, label %cond.test4.1
cond.then4.0:
  %t45 = getelementptr inbounds [6 x i8], ptr @.str.59, i64 0, i64 0
  store ptr %t45, ptr %instr.addr.41, align 8
  br label %cond.end4
cond.test4.1:
  br i1 1, label %cond.then4.1, label %cond.end4
cond.then4.1:
  %t46 = load ptr, ptr %src.addr.2, align 8
  %t47 = call i32 @is-unsigned(ptr %t46)
  %t48 = icmp ne i32 %t47, 0
  br i1 %t48, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t49 = getelementptr inbounds [5 x i8], ptr @.str.60, i64 0, i64 0
  store ptr %t49, ptr %instr.addr.41, align 8
  br label %cond.end5
cond.test5.1:
  br i1 1, label %cond.then5.1, label %cond.end5
cond.then5.1:
  %t50 = getelementptr inbounds [5 x i8], ptr @.str.61, i64 0, i64 0
  store ptr %t50, ptr %instr.addr.41, align 8
  br label %cond.end5
cond.end5:
  br label %cond.end4
cond.end4:
  %t51 = load ptr, ptr @g-body-stream, align 8
  %t52 = getelementptr inbounds [23 x i8], ptr @.str.62, i64 0, i64 0
  %t53 = load ptr, ptr %tmp.addr.39, align 8
  %t54 = load ptr, ptr %instr.addr.41, align 8
  %t55 = load ptr, ptr %src.addr.2, align 8
  %t56 = call ptr @type-to-ir(ptr %t55)
  %t57 = load ptr, ptr %vv.addr.0, align 8
  %t58 = getelementptr inbounds %Val, ptr %t57, i32 0, i32 1
  %t59 = load ptr, ptr %t58, align 8
  %t60 = load ptr, ptr %target.addr, align 8
  %t61 = call ptr @type-to-ir(ptr %t60)
  %t62 = call i32 (ptr, ptr, ...) @fprintf(ptr %t51, ptr %t52, ptr %t53, ptr %t54, ptr %t56, ptr %t59, ptr %t61)
  %t63 = load ptr, ptr %target.addr, align 8
  %t64 = load ptr, ptr %tmp.addr.39, align 8
  %t65 = call ptr @alloc-val(ptr %t63, ptr %t64)
  ret ptr %t65
cond.end1:
  ret ptr null
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
  %t3 = getelementptr inbounds [28 x i8], ptr @.str.63, i64 0, i64 0
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
  %sd.addr.81 = alloca ptr, align 8
  %t.addr.86 = alloca ptr, align 8
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
  %t11 = call ptr @make-type(i32 10)
  store ptr %t11, ptr %p.addr.10, align 8
  %t12 = load ptr, ptr %p.addr.10, align 8
  %t13 = load ptr, ptr %inner.addr.4, align 8
  %t14 = getelementptr inbounds %Type, ptr %t12, i32 0, i32 5
  store ptr %t13, ptr %t14, align 8
  %t15 = load ptr, ptr %p.addr.10, align 8
  ret ptr %t15
cond.end0:
  %t16 = load ptr, ptr %name.addr, align 8
  %t17 = getelementptr inbounds [4 x i8], ptr @.str.64, i64 0, i64 0
  %t18 = call i32 @strcmp(ptr %t16, ptr %t17)
  %t19 = icmp eq i32 %t18, 0
  br i1 %t19, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t20 = load ptr, ptr @ty-i32, align 8
  ret ptr %t20
cond.end1:
  %t21 = load ptr, ptr %name.addr, align 8
  %t22 = getelementptr inbounds [3 x i8], ptr @.str.65, i64 0, i64 0
  %t23 = call i32 @strcmp(ptr %t21, ptr %t22)
  %t24 = icmp eq i32 %t23, 0
  br i1 %t24, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t25 = load ptr, ptr @ty-i1, align 8
  ret ptr %t25
cond.end2:
  %t26 = load ptr, ptr %name.addr, align 8
  %t27 = getelementptr inbounds [3 x i8], ptr @.str.66, i64 0, i64 0
  %t28 = call i32 @strcmp(ptr %t26, ptr %t27)
  %t29 = icmp eq i32 %t28, 0
  br i1 %t29, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t30 = load ptr, ptr @ty-i8, align 8
  ret ptr %t30
cond.end3:
  %t31 = load ptr, ptr %name.addr, align 8
  %t32 = getelementptr inbounds [4 x i8], ptr @.str.67, i64 0, i64 0
  %t33 = call i32 @strcmp(ptr %t31, ptr %t32)
  %t34 = icmp eq i32 %t33, 0
  br i1 %t34, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t35 = load ptr, ptr @ty-i16, align 8
  ret ptr %t35
cond.end4:
  %t36 = load ptr, ptr %name.addr, align 8
  %t37 = getelementptr inbounds [4 x i8], ptr @.str.68, i64 0, i64 0
  %t38 = call i32 @strcmp(ptr %t36, ptr %t37)
  %t39 = icmp eq i32 %t38, 0
  br i1 %t39, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t40 = load ptr, ptr @ty-i32, align 8
  ret ptr %t40
cond.end5:
  %t41 = load ptr, ptr %name.addr, align 8
  %t42 = getelementptr inbounds [4 x i8], ptr @.str.69, i64 0, i64 0
  %t43 = call i32 @strcmp(ptr %t41, ptr %t42)
  %t44 = icmp eq i32 %t43, 0
  br i1 %t44, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t45 = load ptr, ptr @ty-i64, align 8
  ret ptr %t45
cond.end6:
  %t46 = load ptr, ptr %name.addr, align 8
  %t47 = getelementptr inbounds [5 x i8], ptr @.str.70, i64 0, i64 0
  %t48 = call i32 @strcmp(ptr %t46, ptr %t47)
  %t49 = icmp eq i32 %t48, 0
  br i1 %t49, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t50 = load ptr, ptr @ty-i1, align 8
  ret ptr %t50
cond.end7:
  %t51 = load ptr, ptr %name.addr, align 8
  %t52 = getelementptr inbounds [4 x i8], ptr @.str.71, i64 0, i64 0
  %t53 = call i32 @strcmp(ptr %t51, ptr %t52)
  %t54 = icmp eq i32 %t53, 0
  br i1 %t54, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t55 = load ptr, ptr @ty-ptr, align 8
  ret ptr %t55
cond.end8:
  %t56 = load ptr, ptr %name.addr, align 8
  %t57 = getelementptr inbounds [5 x i8], ptr @.str.72, i64 0, i64 0
  %t58 = call i32 @strcmp(ptr %t56, ptr %t57)
  %t59 = icmp eq i32 %t58, 0
  br i1 %t59, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t60 = load ptr, ptr @ty-void, align 8
  ret ptr %t60
cond.end9:
  %t61 = load ptr, ptr %name.addr, align 8
  %t62 = getelementptr inbounds [4 x i8], ptr @.str.73, i64 0, i64 0
  %t63 = call i32 @strcmp(ptr %t61, ptr %t62)
  %t64 = icmp eq i32 %t63, 0
  br i1 %t64, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t65 = load ptr, ptr @ty-ui8, align 8
  ret ptr %t65
cond.end10:
  %t66 = load ptr, ptr %name.addr, align 8
  %t67 = getelementptr inbounds [5 x i8], ptr @.str.74, i64 0, i64 0
  %t68 = call i32 @strcmp(ptr %t66, ptr %t67)
  %t69 = icmp eq i32 %t68, 0
  br i1 %t69, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t70 = load ptr, ptr @ty-ui16, align 8
  ret ptr %t70
cond.end11:
  %t71 = load ptr, ptr %name.addr, align 8
  %t72 = getelementptr inbounds [5 x i8], ptr @.str.75, i64 0, i64 0
  %t73 = call i32 @strcmp(ptr %t71, ptr %t72)
  %t74 = icmp eq i32 %t73, 0
  br i1 %t74, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t75 = load ptr, ptr @ty-ui32, align 8
  ret ptr %t75
cond.end12:
  %t76 = load ptr, ptr %name.addr, align 8
  %t77 = getelementptr inbounds [5 x i8], ptr @.str.76, i64 0, i64 0
  %t78 = call i32 @strcmp(ptr %t76, ptr %t77)
  %t79 = icmp eq i32 %t78, 0
  br i1 %t79, label %cond.then13.0, label %cond.end13
cond.then13.0:
  %t80 = load ptr, ptr @ty-ui64, align 8
  ret ptr %t80
cond.end13:
  %t82 = load ptr, ptr %name.addr, align 8
  %t83 = call ptr @lookup-struct(ptr %t82)
  store ptr %t83, ptr %sd.addr.81, align 8
  %t84 = load ptr, ptr %sd.addr.81, align 8
  %t85 = icmp ne ptr %t84, null
  br i1 %t85, label %cond.then14.0, label %cond.end14
cond.then14.0:
  %t87 = call ptr @make-type(i32 12)
  store ptr %t87, ptr %t.addr.86, align 8
  %t88 = load ptr, ptr %t.addr.86, align 8
  %t89 = load ptr, ptr %sd.addr.81, align 8
  %t90 = getelementptr inbounds %Type, ptr %t88, i32 0, i32 6
  store ptr %t89, ptr %t90, align 8
  %t91 = load ptr, ptr %t.addr.86, align 8
  ret ptr %t91
cond.end14:
  %t92 = load i32, ptr %line.addr, align 4
  %t93 = getelementptr inbounds [17 x i8], ptr @.str.77, i64 0, i64 0
  %t94 = load ptr, ptr %name.addr, align 8
  %t95 = call ptr @fmt-s(ptr %t93, ptr %t94)
  call void @die-at(i32 %t92, ptr %t95)
  ret ptr null
}

define ptr @parse-type-from-node(ptr %node.arg, i32 %line.arg) {
entry:
  %node.addr = alloca ptr, align 8
  store ptr %node.arg, ptr %node.addr, align 8
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %n.addr.0 = alloca ptr, align 8
  %head.addr.15 = alloca ptr, align 8
  %fn-head.addr.25 = alloca ptr, align 8
  %and.val5 = alloca i1, align 1
  %and.val6 = alloca i1, align 1
  %ret-node.addr.43 = alloca ptr, align 8
  %ret-type.addr.47 = alloca ptr, align 8
  %and.val8 = alloca i1, align 1
  %params-node.addr.61 = alloca ptr, align 8
  %num-p.addr.65 = alloca i32, align 4
  %param-arr.addr.66 = alloca ptr, align 8
  %is-va.addr.67 = alloca i32, align 4
  %plist.addr.70 = alloca ptr, align 8
  %cur.addr.76 = alloca ptr, align 8
  %count.addr.78 = alloca i32, align 4
  %pi.addr.93 = alloca i32, align 4
  %ft.addr.110 = alloca ptr, align 8
  %ret-node.addr.135 = alloca ptr, align 8
  %ret-type.addr.139 = alloca ptr, align 8
  %and.val16 = alloca i1, align 1
  %ft.addr.153 = alloca ptr, align 8
  %t1 = load ptr, ptr %node.addr, align 8
  store ptr %t1, ptr %n.addr.0, align 8
  %t2 = load ptr, ptr %n.addr.0, align 8
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 0
  %t4 = load i32, ptr %t3, align 4
  %t5 = icmp eq i32 %t4, 2
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t6 = load ptr, ptr %n.addr.0, align 8
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 3
  %t8 = load ptr, ptr %t7, align 8
  %t9 = load i32, ptr %line.addr, align 4
  %t10 = call ptr @parse-type-name(ptr %t8, i32 %t9)
  ret ptr %t10
cond.end0:
  %t11 = load ptr, ptr %n.addr.0, align 8
  %t12 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 0
  %t13 = load i32, ptr %t12, align 4
  %t14 = icmp eq i32 %t13, 3
  br i1 %t14, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %n.addr.0, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 4
  %t18 = load ptr, ptr %t17, align 8
  store ptr %t18, ptr %head.addr.15, align 8
  %t19 = load ptr, ptr %head.addr.15, align 8
  %t20 = icmp ne ptr %t19, null
  br i1 %t20, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t21 = load ptr, ptr %head.addr.15, align 8
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 0
  %t23 = load i32, ptr %t22, align 4
  %t24 = icmp eq i32 %t23, 3
  br i1 %t24, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t26 = load ptr, ptr %head.addr.15, align 8
  %t27 = getelementptr inbounds %Node, ptr %t26, i32 0, i32 4
  %t28 = load ptr, ptr %t27, align 8
  store ptr %t28, ptr %fn-head.addr.25, align 8
  %t29 = load ptr, ptr %fn-head.addr.25, align 8
  %t30 = icmp ne ptr %t29, null
  store i1 %t30, ptr %and.val5, align 1
  br i1 %t30, label %and.rhs5, label %and.end5
and.rhs5:
  %t31 = load ptr, ptr %fn-head.addr.25, align 8
  %t32 = getelementptr inbounds %Node, ptr %t31, i32 0, i32 0
  %t33 = load i32, ptr %t32, align 4
  %t34 = icmp eq i32 %t33, 2
  store i1 %t34, ptr %and.val6, align 1
  br i1 %t34, label %and.rhs6, label %and.end6
and.rhs6:
  %t35 = load ptr, ptr %fn-head.addr.25, align 8
  %t36 = getelementptr inbounds %Node, ptr %t35, i32 0, i32 3
  %t37 = load ptr, ptr %t36, align 8
  %t38 = getelementptr inbounds [3 x i8], ptr @.str.78, i64 0, i64 0
  %t39 = call i32 @strcmp(ptr %t37, ptr %t38)
  %t40 = icmp eq i32 %t39, 0
  store i1 %t40, ptr %and.val6, align 1
  br label %and.end6
and.end6:
  %t41 = load i1, ptr %and.val6, align 1
  store i1 %t41, ptr %and.val5, align 1
  br label %and.end5
and.end5:
  %t42 = load i1, ptr %and.val5, align 1
  br i1 %t42, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t44 = load ptr, ptr %head.addr.15, align 8
  %t45 = getelementptr inbounds %Node, ptr %t44, i32 0, i32 5
  %t46 = load ptr, ptr %t45, align 8
  store ptr %t46, ptr %ret-node.addr.43, align 8
  %t48 = load ptr, ptr @ty-void, align 8
  store ptr %t48, ptr %ret-type.addr.47, align 8
  %t49 = load ptr, ptr %ret-node.addr.43, align 8
  %t50 = icmp ne ptr %t49, null
  store i1 %t50, ptr %and.val8, align 1
  br i1 %t50, label %and.rhs8, label %and.end8
and.rhs8:
  %t51 = load ptr, ptr %ret-node.addr.43, align 8
  %t52 = getelementptr inbounds %Node, ptr %t51, i32 0, i32 4
  %t53 = load ptr, ptr %t52, align 8
  %t54 = icmp ne ptr %t53, null
  store i1 %t54, ptr %and.val8, align 1
  br label %and.end8
and.end8:
  %t55 = load i1, ptr %and.val8, align 1
  br i1 %t55, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t56 = load ptr, ptr %ret-node.addr.43, align 8
  %t57 = getelementptr inbounds %Node, ptr %t56, i32 0, i32 4
  %t58 = load ptr, ptr %t57, align 8
  %t59 = load i32, ptr %line.addr, align 4
  %t60 = call ptr @parse-type-from-node(ptr %t58, i32 %t59)
  store ptr %t60, ptr %ret-type.addr.47, align 8
  br label %cond.end7
cond.end7:
  %t62 = load ptr, ptr %n.addr.0, align 8
  %t63 = getelementptr inbounds %Node, ptr %t62, i32 0, i32 5
  %t64 = load ptr, ptr %t63, align 8
  store ptr %t64, ptr %params-node.addr.61, align 8
  store i32 0, ptr %num-p.addr.65, align 4
  store ptr null, ptr %param-arr.addr.66, align 8
  store i32 0, ptr %is-va.addr.67, align 4
  %t68 = load ptr, ptr %params-node.addr.61, align 8
  %t69 = icmp ne ptr %t68, null
  br i1 %t69, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t71 = load ptr, ptr %params-node.addr.61, align 8
  %t72 = getelementptr inbounds %Node, ptr %t71, i32 0, i32 4
  %t73 = load ptr, ptr %t72, align 8
  store ptr %t73, ptr %plist.addr.70, align 8
  %t74 = load ptr, ptr %plist.addr.70, align 8
  %t75 = icmp ne ptr %t74, null
  br i1 %t75, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t77 = load ptr, ptr %plist.addr.70, align 8
  store ptr %t77, ptr %cur.addr.76, align 8
  store i32 0, ptr %count.addr.78, align 4
  br label %while.cond11
while.cond11:
  %t79 = load ptr, ptr %cur.addr.76, align 8
  %t80 = icmp ne ptr %t79, null
  br i1 %t80, label %while.body11, label %while.end11
while.body11:
  %t81 = load i32, ptr %count.addr.78, align 4
  %t82 = add nsw i32 %t81, 1
  store i32 %t82, ptr %count.addr.78, align 4
  %t83 = load ptr, ptr %cur.addr.76, align 8
  %t84 = getelementptr inbounds %Node, ptr %t83, i32 0, i32 5
  %t85 = load ptr, ptr %t84, align 8
  store ptr %t85, ptr %cur.addr.76, align 8
  br label %while.cond11
while.end11:
  %t86 = load i32, ptr %count.addr.78, align 4
  store i32 %t86, ptr %num-p.addr.65, align 4
  %t87 = load i32, ptr %count.addr.78, align 4
  %t88 = sext i32 %t87 to i64
  %t89 = sext i32 8 to i64
  %t90 = mul nsw i64 %t88, %t89
  %t91 = call ptr @arena-alloc(i64 %t90)
  store ptr %t91, ptr %param-arr.addr.66, align 8
  %t92 = load ptr, ptr %plist.addr.70, align 8
  store ptr %t92, ptr %cur.addr.76, align 8
  store i32 0, ptr %pi.addr.93, align 4
  br label %while.cond12
while.cond12:
  %t94 = load ptr, ptr %cur.addr.76, align 8
  %t95 = icmp ne ptr %t94, null
  br i1 %t95, label %while.body12, label %while.end12
while.body12:
  %t96 = load ptr, ptr %param-arr.addr.66, align 8
  %t97 = load i32, ptr %pi.addr.93, align 4
  %t98 = sext i32 %t97 to i64
  %t99 = load ptr, ptr %cur.addr.76, align 8
  %t100 = getelementptr inbounds %Node, ptr %t99, i32 0, i32 4
  %t101 = load ptr, ptr %t100, align 8
  %t102 = load i32, ptr %line.addr, align 4
  %t103 = call ptr @parse-type-from-node(ptr %t101, i32 %t102)
  %t104 = getelementptr inbounds ptr, ptr %t96, i64 %t98
  store ptr %t103, ptr %t104, align 8
  %t105 = load i32, ptr %pi.addr.93, align 4
  %t106 = add nsw i32 %t105, 1
  store i32 %t106, ptr %pi.addr.93, align 4
  %t107 = load ptr, ptr %cur.addr.76, align 8
  %t108 = getelementptr inbounds %Node, ptr %t107, i32 0, i32 5
  %t109 = load ptr, ptr %t108, align 8
  store ptr %t109, ptr %cur.addr.76, align 8
  br label %while.cond12
while.end12:
  br label %cond.end10
cond.end10:
  br label %cond.end9
cond.end9:
  %t111 = call ptr @make-type(i32 11)
  store ptr %t111, ptr %ft.addr.110, align 8
  %t112 = load ptr, ptr %ft.addr.110, align 8
  %t113 = load ptr, ptr %ret-type.addr.47, align 8
  %t114 = getelementptr inbounds %Type, ptr %t112, i32 0, i32 1
  store ptr %t113, ptr %t114, align 8
  %t115 = load ptr, ptr %ft.addr.110, align 8
  %t116 = load ptr, ptr %param-arr.addr.66, align 8
  %t117 = getelementptr inbounds %Type, ptr %t115, i32 0, i32 2
  store ptr %t116, ptr %t117, align 8
  %t118 = load ptr, ptr %ft.addr.110, align 8
  %t119 = load i32, ptr %num-p.addr.65, align 4
  %t120 = getelementptr inbounds %Type, ptr %t118, i32 0, i32 3
  store i32 %t119, ptr %t120, align 4
  %t121 = load ptr, ptr %ft.addr.110, align 8
  %t122 = load i32, ptr %is-va.addr.67, align 4
  %t123 = getelementptr inbounds %Type, ptr %t121, i32 0, i32 4
  store i32 %t122, ptr %t123, align 4
  %t124 = load ptr, ptr %ft.addr.110, align 8
  ret ptr %t124
cond.end4:
  br label %cond.end3
cond.end3:
  %t125 = load ptr, ptr %head.addr.15, align 8
  %t126 = getelementptr inbounds %Node, ptr %t125, i32 0, i32 0
  %t127 = load i32, ptr %t126, align 4
  %t128 = icmp eq i32 %t127, 2
  br i1 %t128, label %cond.then13.0, label %cond.end13
cond.then13.0:
  %t129 = load ptr, ptr %head.addr.15, align 8
  %t130 = getelementptr inbounds %Node, ptr %t129, i32 0, i32 3
  %t131 = load ptr, ptr %t130, align 8
  %t132 = getelementptr inbounds [3 x i8], ptr @.str.79, i64 0, i64 0
  %t133 = call i32 @strcmp(ptr %t131, ptr %t132)
  %t134 = icmp eq i32 %t133, 0
  br i1 %t134, label %cond.then14.0, label %cond.end14
cond.then14.0:
  %t136 = load ptr, ptr %n.addr.0, align 8
  %t137 = getelementptr inbounds %Node, ptr %t136, i32 0, i32 5
  %t138 = load ptr, ptr %t137, align 8
  store ptr %t138, ptr %ret-node.addr.135, align 8
  %t140 = load ptr, ptr @ty-void, align 8
  store ptr %t140, ptr %ret-type.addr.139, align 8
  %t141 = load ptr, ptr %ret-node.addr.135, align 8
  %t142 = icmp ne ptr %t141, null
  store i1 %t142, ptr %and.val16, align 1
  br i1 %t142, label %and.rhs16, label %and.end16
and.rhs16:
  %t143 = load ptr, ptr %ret-node.addr.135, align 8
  %t144 = getelementptr inbounds %Node, ptr %t143, i32 0, i32 4
  %t145 = load ptr, ptr %t144, align 8
  %t146 = icmp ne ptr %t145, null
  store i1 %t146, ptr %and.val16, align 1
  br label %and.end16
and.end16:
  %t147 = load i1, ptr %and.val16, align 1
  br i1 %t147, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t148 = load ptr, ptr %ret-node.addr.135, align 8
  %t149 = getelementptr inbounds %Node, ptr %t148, i32 0, i32 4
  %t150 = load ptr, ptr %t149, align 8
  %t151 = load i32, ptr %line.addr, align 4
  %t152 = call ptr @parse-type-from-node(ptr %t150, i32 %t151)
  store ptr %t152, ptr %ret-type.addr.139, align 8
  br label %cond.end15
cond.end15:
  %t154 = call ptr @make-type(i32 11)
  store ptr %t154, ptr %ft.addr.153, align 8
  %t155 = load ptr, ptr %ft.addr.153, align 8
  %t156 = load ptr, ptr %ret-type.addr.139, align 8
  %t157 = getelementptr inbounds %Type, ptr %t155, i32 0, i32 1
  store ptr %t156, ptr %t157, align 8
  %t158 = load ptr, ptr %ft.addr.153, align 8
  %t159 = getelementptr inbounds %Type, ptr %t158, i32 0, i32 2
  store ptr null, ptr %t159, align 8
  %t160 = load ptr, ptr %ft.addr.153, align 8
  %t161 = getelementptr inbounds %Type, ptr %t160, i32 0, i32 3
  store i32 0, ptr %t161, align 4
  %t162 = load ptr, ptr %ft.addr.153, align 8
  %t163 = getelementptr inbounds %Type, ptr %t162, i32 0, i32 4
  store i32 0, ptr %t163, align 4
  %t164 = load ptr, ptr %ft.addr.153, align 8
  ret ptr %t164
cond.end14:
  br label %cond.end13
cond.end13:
  br label %cond.end2
cond.end2:
  br label %cond.end1
cond.end1:
  %t165 = load i32, ptr %line.addr, align 4
  %t166 = getelementptr inbounds [32 x i8], ptr @.str.80, i64 0, i64 0
  call void @die-at(i32 %t165, ptr %t166)
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

define void @extract-name-type(ptr %node.arg, ptr %out-name.arg, ptr %out-type-name.arg) {
entry:
  %node.addr = alloca ptr, align 8
  store ptr %node.arg, ptr %node.addr, align 8
  %out-name.addr = alloca ptr, align 8
  store ptr %out-name.arg, ptr %out-name.addr, align 8
  %out-type-name.addr = alloca ptr, align 8
  store ptr %out-type-name.arg, ptr %out-type-name.addr, align 8
  %n.addr.0 = alloca ptr, align 8
  %car-node.addr.15 = alloca ptr, align 8
  %and.val3 = alloca i1, align 1
  %rest.addr.30 = alloca ptr, align 8
  %type-node.addr.36 = alloca ptr, align 8
  %and.val6 = alloca i1, align 1
  %t1 = load ptr, ptr %node.addr, align 8
  store ptr %t1, ptr %n.addr.0, align 8
  %t2 = load ptr, ptr %n.addr.0, align 8
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 0
  %t4 = load i32, ptr %t3, align 4
  %t5 = icmp eq i32 %t4, 2
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t6 = load ptr, ptr %n.addr.0, align 8
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 3
  %t8 = load ptr, ptr %t7, align 8
  %t9 = load ptr, ptr %out-name.addr, align 8
  %t10 = load ptr, ptr %out-type-name.addr, align 8
  call void @split-typed(ptr %t8, ptr %t9, ptr %t10)
  ret void
cond.end0:
  %t11 = load ptr, ptr %n.addr.0, align 8
  %t12 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 0
  %t13 = load i32, ptr %t12, align 4
  %t14 = icmp eq i32 %t13, 3
  br i1 %t14, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr %n.addr.0, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 4
  %t18 = load ptr, ptr %t17, align 8
  store ptr %t18, ptr %car-node.addr.15, align 8
  %t19 = load ptr, ptr %car-node.addr.15, align 8
  %t20 = icmp ne ptr %t19, null
  store i1 %t20, ptr %and.val3, align 1
  br i1 %t20, label %and.rhs3, label %and.end3
and.rhs3:
  %t21 = load ptr, ptr %car-node.addr.15, align 8
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 0
  %t23 = load i32, ptr %t22, align 4
  %t24 = icmp eq i32 %t23, 2
  store i1 %t24, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t25 = load i1, ptr %and.val3, align 1
  br i1 %t25, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t26 = load ptr, ptr %out-name.addr, align 8
  %t27 = load ptr, ptr %car-node.addr.15, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 3
  %t29 = load ptr, ptr %t28, align 8
  store ptr %t29, ptr %t26, align 8
  %t31 = load ptr, ptr %n.addr.0, align 8
  %t32 = getelementptr inbounds %Node, ptr %t31, i32 0, i32 5
  %t33 = load ptr, ptr %t32, align 8
  store ptr %t33, ptr %rest.addr.30, align 8
  %t34 = load ptr, ptr %rest.addr.30, align 8
  %t35 = icmp ne ptr %t34, null
  br i1 %t35, label %cond.then4.0, label %cond.test4.1
cond.then4.0:
  %t37 = load ptr, ptr %rest.addr.30, align 8
  %t38 = getelementptr inbounds %Node, ptr %t37, i32 0, i32 4
  %t39 = load ptr, ptr %t38, align 8
  store ptr %t39, ptr %type-node.addr.36, align 8
  %t40 = load ptr, ptr %type-node.addr.36, align 8
  %t41 = icmp ne ptr %t40, null
  store i1 %t41, ptr %and.val6, align 1
  br i1 %t41, label %and.rhs6, label %and.end6
and.rhs6:
  %t42 = load ptr, ptr %type-node.addr.36, align 8
  %t43 = getelementptr inbounds %Node, ptr %t42, i32 0, i32 0
  %t44 = load i32, ptr %t43, align 4
  %t45 = icmp eq i32 %t44, 2
  store i1 %t45, ptr %and.val6, align 1
  br label %and.end6
and.end6:
  %t46 = load i1, ptr %and.val6, align 1
  br i1 %t46, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t47 = load ptr, ptr %out-type-name.addr, align 8
  %t48 = load ptr, ptr %type-node.addr.36, align 8
  %t49 = getelementptr inbounds %Node, ptr %t48, i32 0, i32 3
  %t50 = load ptr, ptr %t49, align 8
  store ptr %t50, ptr %t47, align 8
  br label %cond.end5
cond.end5:
  ret void
cond.test4.1:
  br i1 1, label %cond.then4.1, label %cond.end4
cond.then4.1:
  %t51 = load ptr, ptr %out-type-name.addr, align 8
  store ptr null, ptr %t51, align 8
  ret void
cond.end4:
  br label %cond.end2
cond.end2:
  br label %cond.end1
cond.end1:
  %t52 = load ptr, ptr %out-name.addr, align 8
  store ptr null, ptr %t52, align 8
  %t53 = load ptr, ptr %out-type-name.addr, align 8
  store ptr null, ptr %t53, align 8
  ret void
}

define ptr @extract-name-and-type(ptr %node.arg, ptr %out-name.arg, i32 %line.arg) {
entry:
  %node.addr = alloca ptr, align 8
  store ptr %node.arg, ptr %node.addr, align 8
  %out-name.addr = alloca ptr, align 8
  store ptr %out-name.arg, ptr %out-name.addr, align 8
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %n.addr.0 = alloca ptr, align 8
  %tname.addr.6 = alloca ptr, align 8
  %car-node.addr.20 = alloca ptr, align 8
  %and.val4 = alloca i1, align 1
  %rest.addr.35 = alloca ptr, align 8
  %type-node.addr.41 = alloca ptr, align 8
  %t1 = load ptr, ptr %node.addr, align 8
  store ptr %t1, ptr %n.addr.0, align 8
  %t2 = load ptr, ptr %n.addr.0, align 8
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 0
  %t4 = load i32, ptr %t3, align 4
  %t5 = icmp eq i32 %t4, 2
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  store ptr null, ptr %tname.addr.6, align 8
  %t7 = load ptr, ptr %n.addr.0, align 8
  %t8 = getelementptr inbounds %Node, ptr %t7, i32 0, i32 3
  %t9 = load ptr, ptr %t8, align 8
  %t10 = load ptr, ptr %out-name.addr, align 8
  call void @split-typed(ptr %t9, ptr %t10, ptr %tname.addr.6)
  %t11 = load ptr, ptr %tname.addr.6, align 8
  %t12 = icmp ne ptr %t11, null
  br i1 %t12, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t13 = load ptr, ptr %tname.addr.6, align 8
  %t14 = load i32, ptr %line.addr, align 4
  %t15 = call ptr @parse-type-name(ptr %t13, i32 %t14)
  ret ptr %t15
cond.end1:
  ret ptr null
cond.end0:
  %t16 = load ptr, ptr %n.addr.0, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp eq i32 %t18, 3
  br i1 %t19, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t21 = load ptr, ptr %n.addr.0, align 8
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 4
  %t23 = load ptr, ptr %t22, align 8
  store ptr %t23, ptr %car-node.addr.20, align 8
  %t24 = load ptr, ptr %car-node.addr.20, align 8
  %t25 = icmp ne ptr %t24, null
  store i1 %t25, ptr %and.val4, align 1
  br i1 %t25, label %and.rhs4, label %and.end4
and.rhs4:
  %t26 = load ptr, ptr %car-node.addr.20, align 8
  %t27 = getelementptr inbounds %Node, ptr %t26, i32 0, i32 0
  %t28 = load i32, ptr %t27, align 4
  %t29 = icmp eq i32 %t28, 2
  store i1 %t29, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t30 = load i1, ptr %and.val4, align 1
  br i1 %t30, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t31 = load ptr, ptr %out-name.addr, align 8
  %t32 = load ptr, ptr %car-node.addr.20, align 8
  %t33 = getelementptr inbounds %Node, ptr %t32, i32 0, i32 3
  %t34 = load ptr, ptr %t33, align 8
  store ptr %t34, ptr %t31, align 8
  %t36 = load ptr, ptr %n.addr.0, align 8
  %t37 = getelementptr inbounds %Node, ptr %t36, i32 0, i32 5
  %t38 = load ptr, ptr %t37, align 8
  store ptr %t38, ptr %rest.addr.35, align 8
  %t39 = load ptr, ptr %rest.addr.35, align 8
  %t40 = icmp eq ptr %t39, null
  br i1 %t40, label %cond.then5.0, label %cond.end5
cond.then5.0:
  ret ptr null
cond.end5:
  %t42 = load ptr, ptr %rest.addr.35, align 8
  %t43 = getelementptr inbounds %Node, ptr %t42, i32 0, i32 4
  %t44 = load ptr, ptr %t43, align 8
  store ptr %t44, ptr %type-node.addr.41, align 8
  %t45 = load ptr, ptr %type-node.addr.41, align 8
  %t46 = icmp eq ptr %t45, null
  br i1 %t46, label %cond.then6.0, label %cond.end6
cond.then6.0:
  ret ptr null
cond.end6:
  %t47 = load ptr, ptr %type-node.addr.41, align 8
  %t48 = getelementptr inbounds %Node, ptr %t47, i32 0, i32 0
  %t49 = load i32, ptr %t48, align 4
  %t50 = icmp eq i32 %t49, 2
  br i1 %t50, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t51 = load ptr, ptr %type-node.addr.41, align 8
  %t52 = getelementptr inbounds %Node, ptr %t51, i32 0, i32 3
  %t53 = load ptr, ptr %t52, align 8
  %t54 = load i32, ptr %line.addr, align 4
  %t55 = call ptr @parse-type-name(ptr %t53, i32 %t54)
  ret ptr %t55
cond.end7:
  %t56 = load ptr, ptr %type-node.addr.41, align 8
  %t57 = getelementptr inbounds %Node, ptr %t56, i32 0, i32 0
  %t58 = load i32, ptr %t57, align 4
  %t59 = icmp eq i32 %t58, 3
  br i1 %t59, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t60 = load ptr, ptr %rest.addr.35, align 8
  %t61 = load i32, ptr %line.addr, align 4
  %t62 = call ptr @parse-type-from-node(ptr %t60, i32 %t61)
  ret ptr %t62
cond.end8:
  ret ptr null
cond.end3:
  br label %cond.end2
cond.end2:
  %t63 = load ptr, ptr %out-name.addr, align 8
  store ptr null, ptr %t63, align 8
  ret ptr null
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
  %t19 = getelementptr inbounds [7 x i8], ptr @.str.81, i64 0, i64 0
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
  %t1 = getelementptr inbounds [6 x i8], ptr @.str.82, i64 0, i64 0
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
  %t1 = getelementptr inbounds [4 x i8], ptr @.str.83, i64 0, i64 0
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
  %t23 = getelementptr inbounds [69 x i8], ptr @.str.84, i64 0, i64 0
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
  %t2 = getelementptr inbounds [5 x i8], ptr @.str.85, i64 0, i64 0
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
  %t14 = getelementptr inbounds [138 x i8], ptr @.str.86, i64 0, i64 0
  %t15 = load i32, ptr %id.addr.9, align 4
  %t16 = load ptr, ptr %nn.addr.3, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 1
  %t18 = load i32, ptr %t17, align 4
  %t19 = load ptr, ptr %nn.addr.3, align 8
  %t20 = getelementptr inbounds %Node, ptr %t19, i32 0, i32 2
  %t21 = load i64, ptr %t20, align 8
  %t22 = call i32 (ptr, ptr, ...) @fprintf(ptr %t13, ptr %t14, i32 %t15, i32 %t18, i64 %t21)
  %t23 = getelementptr inbounds [7 x i8], ptr @.str.87, i64 0, i64 0
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
  %t64 = getelementptr inbounds [195 x i8], ptr @.str.88, i64 0, i64 0
  %t65 = load i32, ptr %id.addr.59, align 4
  %t66 = load i32, ptr %k.addr.36, align 4
  %t67 = load ptr, ptr %nn.addr.3, align 8
  %t68 = getelementptr inbounds %Node, ptr %t67, i32 0, i32 1
  %t69 = load i32, ptr %t68, align 4
  %t70 = load i32, ptr %ir-len.addr.51, align 4
  %t71 = load i32, ptr %sid.addr.41, align 4
  %t72 = call i32 (ptr, ptr, ...) @fprintf(ptr %t63, ptr %t64, i32 %t65, i32 %t66, i32 %t69, i32 %t70, i32 %t71)
  %t73 = getelementptr inbounds [7 x i8], ptr @.str.89, i64 0, i64 0
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
  %t92 = getelementptr inbounds [132 x i8], ptr @.str.90, i64 0, i64 0
  %t93 = load i32, ptr %id.addr.87, align 4
  %t94 = load ptr, ptr %nn.addr.3, align 8
  %t95 = getelementptr inbounds %Node, ptr %t94, i32 0, i32 1
  %t96 = load i32, ptr %t95, align 4
  %t97 = load ptr, ptr %car-ref.addr.77, align 8
  %t98 = load ptr, ptr %cdr-ref.addr.82, align 8
  %t99 = call i32 (ptr, ptr, ...) @fprintf(ptr %t91, ptr %t92, i32 %t93, i32 %t96, ptr %t97, ptr %t98)
  %t100 = getelementptr inbounds [7 x i8], ptr @.str.91, i64 0, i64 0
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
  %t8 = getelementptr inbounds [21 x i8], ptr @.str.92, i64 0, i64 0
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
  %t3 = getelementptr inbounds [5 x i8], ptr @.str.93, i64 0, i64 0
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
  %t12 = getelementptr inbounds [15 x i8], ptr @.str.94, i64 0, i64 0
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
  %t31 = getelementptr inbounds [43 x i8], ptr @.str.95, i64 0, i64 0
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
  %t56 = getelementptr inbounds [41 x i8], ptr @.str.96, i64 0, i64 0
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
  %t3 = getelementptr inbounds [5 x i8], ptr @.str.97, i64 0, i64 0
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
  %t18 = getelementptr inbounds [8 x i8], ptr @.str.98, i64 0, i64 0
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
  %t26 = getelementptr inbounds [15 x i8], ptr @.str.99, i64 0, i64 0
  %t27 = call i32 @qq-is-tagged(ptr %t25, ptr %t26)
  %t28 = icmp ne i32 %t27, 0
  br i1 %t28, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t29 = load ptr, ptr %fn.addr.5, align 8
  %t30 = getelementptr inbounds %Node, ptr %t29, i32 0, i32 1
  %t31 = load i32, ptr %t30, align 4
  %t32 = getelementptr inbounds [28 x i8], ptr @.str.100, i64 0, i64 0
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
  %t8 = getelementptr inbounds [26 x i8], ptr @.str.101, i64 0, i64 0
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
  %tmp.addr.84 = alloca ptr, align 8
  %t1 = load ptr, ptr %n.addr, align 8
  store ptr %t1, ptr %nn.addr.0, align 8
  %t2 = load ptr, ptr %nn.addr.0, align 8
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 3
  %t4 = load ptr, ptr %t3, align 8
  %t5 = getelementptr inbounds [5 x i8], ptr @.str.102, i64 0, i64 0
  %t6 = call i32 @strcmp(ptr %t4, ptr %t5)
  %t7 = icmp eq i32 %t6, 0
  br i1 %t7, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t8 = load ptr, ptr @ty-ptr, align 8
  %t9 = getelementptr inbounds [5 x i8], ptr @.str.103, i64 0, i64 0
  %t10 = call ptr @alloc-val(ptr %t8, ptr %t9)
  ret ptr %t10
cond.end0:
  %t11 = load ptr, ptr %nn.addr.0, align 8
  %t12 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 3
  %t13 = load ptr, ptr %t12, align 8
  %t14 = getelementptr inbounds [5 x i8], ptr @.str.104, i64 0, i64 0
  %t15 = call i32 @strcmp(ptr %t13, ptr %t14)
  %t16 = icmp eq i32 %t15, 0
  br i1 %t16, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t17 = load ptr, ptr @ty-i1, align 8
  %t18 = getelementptr inbounds [2 x i8], ptr @.str.105, i64 0, i64 0
  %t19 = call ptr @alloc-val(ptr %t17, ptr %t18)
  ret ptr %t19
cond.end1:
  %t20 = load ptr, ptr %nn.addr.0, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 3
  %t22 = load ptr, ptr %t21, align 8
  %t23 = getelementptr inbounds [6 x i8], ptr @.str.106, i64 0, i64 0
  %t24 = call i32 @strcmp(ptr %t22, ptr %t23)
  %t25 = icmp eq i32 %t24, 0
  br i1 %t25, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t26 = load ptr, ptr @ty-i1, align 8
  %t27 = getelementptr inbounds [2 x i8], ptr @.str.107, i64 0, i64 0
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
  %t43 = getelementptr inbounds [14 x i8], ptr @.str.108, i64 0, i64 0
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
  %t63 = load ptr, ptr %sym.addr.34, align 8
  %t64 = getelementptr inbounds %Sym, ptr %t63, i32 0, i32 1
  %t65 = load ptr, ptr %t64, align 8
  %t66 = getelementptr inbounds %Type, ptr %t65, i32 0, i32 0
  %t67 = load i32, ptr %t66, align 4
  %t68 = icmp eq i32 %t67, 11
  br i1 %t68, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t69 = load ptr, ptr %sym.addr.34, align 8
  %t70 = getelementptr inbounds %Sym, ptr %t69, i32 0, i32 1
  %t71 = load ptr, ptr %t70, align 8
  %t72 = load ptr, ptr %sym.addr.34, align 8
  %t73 = getelementptr inbounds %Sym, ptr %t72, i32 0, i32 2
  %t74 = load ptr, ptr %t73, align 8
  %t75 = call ptr @alloc-val(ptr %t71, ptr %t74)
  ret ptr %t75
cond.end6:
  %t76 = load ptr, ptr %nn.addr.0, align 8
  %t77 = getelementptr inbounds %Node, ptr %t76, i32 0, i32 1
  %t78 = load i32, ptr %t77, align 4
  %t79 = getelementptr inbounds [25 x i8], ptr @.str.109, i64 0, i64 0
  %t80 = load ptr, ptr %nn.addr.0, align 8
  %t81 = getelementptr inbounds %Node, ptr %t80, i32 0, i32 3
  %t82 = load ptr, ptr %t81, align 8
  %t83 = call ptr @fmt-s(ptr %t79, ptr %t82)
  call void @die-at(i32 %t78, ptr %t83)
  br label %cond.end5
cond.end5:
  %t85 = call ptr @new-tmp()
  store ptr %t85, ptr %tmp.addr.84, align 8
  %t86 = load ptr, ptr @g-body-stream, align 8
  %t87 = getelementptr inbounds [34 x i8], ptr @.str.110, i64 0, i64 0
  %t88 = load ptr, ptr %tmp.addr.84, align 8
  %t89 = load ptr, ptr %sym.addr.34, align 8
  %t90 = getelementptr inbounds %Sym, ptr %t89, i32 0, i32 1
  %t91 = load ptr, ptr %t90, align 8
  %t92 = call ptr @type-to-ir(ptr %t91)
  %t93 = load ptr, ptr %sym.addr.34, align 8
  %t94 = getelementptr inbounds %Sym, ptr %t93, i32 0, i32 2
  %t95 = load ptr, ptr %t94, align 8
  %t96 = load ptr, ptr %sym.addr.34, align 8
  %t97 = getelementptr inbounds %Sym, ptr %t96, i32 0, i32 1
  %t98 = load ptr, ptr %t97, align 8
  %t99 = call i32 @type-size(ptr %t98)
  %t100 = call i32 (ptr, ptr, ...) @fprintf(ptr %t86, ptr %t87, ptr %t88, ptr %t92, ptr %t95, i32 %t99)
  %t101 = load ptr, ptr %sym.addr.34, align 8
  %t102 = getelementptr inbounds %Sym, ptr %t101, i32 0, i32 1
  %t103 = load ptr, ptr %t102, align 8
  %t104 = load ptr, ptr %tmp.addr.84, align 8
  %t105 = call ptr @alloc-val(ptr %t103, ptr %t104)
  ret ptr %t105
}

define void @add-binop(ptr %name.arg, ptr %instr.arg, ptr %instr-u.arg, i32 %is-cmp.arg) {
entry:
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %instr.addr = alloca ptr, align 8
  store ptr %instr.arg, ptr %instr.addr, align 8
  %instr-u.addr = alloca ptr, align 8
  store ptr %instr-u.arg, ptr %instr-u.addr, align 8
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
  %t12 = load ptr, ptr %instr-u.addr, align 8
  %t13 = getelementptr inbounds %BinOp, ptr %t11, i32 0, i32 2
  store ptr %t12, ptr %t13, align 8
  %t14 = load ptr, ptr %op.addr.0, align 8
  %t15 = load i32, ptr %is-cmp.addr, align 4
  %t16 = getelementptr inbounds %BinOp, ptr %t14, i32 0, i32 3
  store i32 %t15, ptr %t16, align 4
  %t17 = load i32, ptr @g-num-binops, align 4
  %t18 = add nsw i32 %t17, 1
  store i32 %t18, ptr @g-num-binops, align 4
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
  %t5 = getelementptr inbounds [2 x i8], ptr @.str.111, i64 0, i64 0
  %t6 = getelementptr inbounds [8 x i8], ptr @.str.112, i64 0, i64 0
  %t7 = getelementptr inbounds [4 x i8], ptr @.str.113, i64 0, i64 0
  call void @add-binop(ptr %t5, ptr %t6, ptr %t7, i32 0)
  %t8 = getelementptr inbounds [2 x i8], ptr @.str.114, i64 0, i64 0
  %t9 = getelementptr inbounds [8 x i8], ptr @.str.115, i64 0, i64 0
  %t10 = getelementptr inbounds [4 x i8], ptr @.str.116, i64 0, i64 0
  call void @add-binop(ptr %t8, ptr %t9, ptr %t10, i32 0)
  %t11 = getelementptr inbounds [2 x i8], ptr @.str.117, i64 0, i64 0
  %t12 = getelementptr inbounds [8 x i8], ptr @.str.118, i64 0, i64 0
  %t13 = getelementptr inbounds [4 x i8], ptr @.str.119, i64 0, i64 0
  call void @add-binop(ptr %t11, ptr %t12, ptr %t13, i32 0)
  %t14 = getelementptr inbounds [2 x i8], ptr @.str.120, i64 0, i64 0
  %t15 = getelementptr inbounds [5 x i8], ptr @.str.121, i64 0, i64 0
  %t16 = getelementptr inbounds [5 x i8], ptr @.str.122, i64 0, i64 0
  call void @add-binop(ptr %t14, ptr %t15, ptr %t16, i32 0)
  %t17 = getelementptr inbounds [2 x i8], ptr @.str.123, i64 0, i64 0
  %t18 = getelementptr inbounds [5 x i8], ptr @.str.124, i64 0, i64 0
  %t19 = getelementptr inbounds [5 x i8], ptr @.str.125, i64 0, i64 0
  call void @add-binop(ptr %t17, ptr %t18, ptr %t19, i32 0)
  %t20 = getelementptr inbounds [8 x i8], ptr @.str.126, i64 0, i64 0
  %t21 = getelementptr inbounds [4 x i8], ptr @.str.127, i64 0, i64 0
  %t22 = getelementptr inbounds [4 x i8], ptr @.str.128, i64 0, i64 0
  call void @add-binop(ptr %t20, ptr %t21, ptr %t22, i32 0)
  %t23 = getelementptr inbounds [7 x i8], ptr @.str.129, i64 0, i64 0
  %t24 = getelementptr inbounds [3 x i8], ptr @.str.130, i64 0, i64 0
  %t25 = getelementptr inbounds [3 x i8], ptr @.str.131, i64 0, i64 0
  call void @add-binop(ptr %t23, ptr %t24, ptr %t25, i32 0)
  %t26 = getelementptr inbounds [8 x i8], ptr @.str.132, i64 0, i64 0
  %t27 = getelementptr inbounds [4 x i8], ptr @.str.133, i64 0, i64 0
  %t28 = getelementptr inbounds [4 x i8], ptr @.str.134, i64 0, i64 0
  call void @add-binop(ptr %t26, ptr %t27, ptr %t28, i32 0)
  %t29 = getelementptr inbounds [8 x i8], ptr @.str.135, i64 0, i64 0
  %t30 = getelementptr inbounds [4 x i8], ptr @.str.136, i64 0, i64 0
  %t31 = getelementptr inbounds [4 x i8], ptr @.str.137, i64 0, i64 0
  call void @add-binop(ptr %t29, ptr %t30, ptr %t31, i32 0)
  %t32 = getelementptr inbounds [8 x i8], ptr @.str.138, i64 0, i64 0
  %t33 = getelementptr inbounds [5 x i8], ptr @.str.139, i64 0, i64 0
  %t34 = getelementptr inbounds [5 x i8], ptr @.str.140, i64 0, i64 0
  call void @add-binop(ptr %t32, ptr %t33, ptr %t34, i32 0)
  %t35 = getelementptr inbounds [2 x i8], ptr @.str.141, i64 0, i64 0
  %t36 = getelementptr inbounds [8 x i8], ptr @.str.142, i64 0, i64 0
  %t37 = getelementptr inbounds [8 x i8], ptr @.str.143, i64 0, i64 0
  call void @add-binop(ptr %t35, ptr %t36, ptr %t37, i32 1)
  %t38 = getelementptr inbounds [3 x i8], ptr @.str.144, i64 0, i64 0
  %t39 = getelementptr inbounds [8 x i8], ptr @.str.145, i64 0, i64 0
  %t40 = getelementptr inbounds [8 x i8], ptr @.str.146, i64 0, i64 0
  call void @add-binop(ptr %t38, ptr %t39, ptr %t40, i32 1)
  %t41 = getelementptr inbounds [2 x i8], ptr @.str.147, i64 0, i64 0
  %t42 = getelementptr inbounds [9 x i8], ptr @.str.148, i64 0, i64 0
  %t43 = getelementptr inbounds [9 x i8], ptr @.str.149, i64 0, i64 0
  call void @add-binop(ptr %t41, ptr %t42, ptr %t43, i32 1)
  %t44 = getelementptr inbounds [3 x i8], ptr @.str.150, i64 0, i64 0
  %t45 = getelementptr inbounds [9 x i8], ptr @.str.151, i64 0, i64 0
  %t46 = getelementptr inbounds [9 x i8], ptr @.str.152, i64 0, i64 0
  call void @add-binop(ptr %t44, ptr %t45, ptr %t46, i32 1)
  %t47 = getelementptr inbounds [2 x i8], ptr @.str.153, i64 0, i64 0
  %t48 = getelementptr inbounds [9 x i8], ptr @.str.154, i64 0, i64 0
  %t49 = getelementptr inbounds [9 x i8], ptr @.str.155, i64 0, i64 0
  call void @add-binop(ptr %t47, ptr %t48, ptr %t49, i32 1)
  %t50 = getelementptr inbounds [3 x i8], ptr @.str.156, i64 0, i64 0
  %t51 = getelementptr inbounds [9 x i8], ptr @.str.157, i64 0, i64 0
  %t52 = getelementptr inbounds [9 x i8], ptr @.str.158, i64 0, i64 0
  call void @add-binop(ptr %t50, ptr %t51, ptr %t52, i32 1)
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
  %tmp.addr.115 = alloca ptr, align 8
  %instr.addr.117 = alloca ptr, align 8
  %rtype.addr.144 = alloca ptr, align 8
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
  %t10 = getelementptr inbounds [18 x i8], ptr @.str.159, i64 0, i64 0
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
  %t30 = icmp eq i32 %t29, 10
  store i1 %t30, ptr %and.val2, align 1
  br i1 %t30, label %and.rhs2, label %and.end2
and.rhs2:
  %t31 = load ptr, ptr %b.addr.20, align 8
  %t32 = getelementptr inbounds %Val, ptr %t31, i32 0, i32 0
  %t33 = load ptr, ptr %t32, align 8
  %t34 = getelementptr inbounds %Type, ptr %t33, i32 0, i32 0
  %t35 = load i32, ptr %t34, align 4
  %t36 = icmp eq i32 %t35, 10
  store i1 %t36, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t37 = load i1, ptr %and.val2, align 1
  br i1 %t37, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t38 = load ptr, ptr %bop.addr.2, align 8
  %t39 = getelementptr inbounds %BinOp, ptr %t38, i32 0, i32 3
  %t40 = load i32, ptr %t39, align 4
  %t41 = icmp ne i32 %t40, 0
  br i1 %t41, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t43 = call ptr @new-tmp()
  store ptr %t43, ptr %tmp.addr.42, align 8
  %t44 = load ptr, ptr @g-body-stream, align 8
  %t45 = getelementptr inbounds [22 x i8], ptr @.str.160, i64 0, i64 0
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
  %t74 = getelementptr inbounds [28 x i8], ptr @.str.161, i64 0, i64 0
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
  %t82 = call i32 @is-unsigned(ptr %t81)
  %t83 = load ptr, ptr %b.addr.20, align 8
  %t84 = getelementptr inbounds %Val, ptr %t83, i32 0, i32 0
  %t85 = load ptr, ptr %t84, align 8
  %t86 = call i32 @is-unsigned(ptr %t85)
  %t87 = icmp ne i32 %t82, %t86
  br i1 %t87, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t88 = load ptr, ptr %cc.addr.0, align 8
  %t89 = getelementptr inbounds %Node, ptr %t88, i32 0, i32 1
  %t90 = load i32, ptr %t89, align 4
  %t91 = getelementptr inbounds [57 x i8], ptr @.str.162, i64 0, i64 0
  %t92 = load ptr, ptr %bop.addr.2, align 8
  %t93 = getelementptr inbounds %BinOp, ptr %t92, i32 0, i32 0
  %t94 = load ptr, ptr %t93, align 8
  %t95 = call ptr @fmt-s(ptr %t91, ptr %t94)
  call void @die-at(i32 %t90, ptr %t95)
  br label %cond.end6
cond.end6:
  %t96 = load ptr, ptr %a.addr.15, align 8
  %t97 = getelementptr inbounds %Val, ptr %t96, i32 0, i32 0
  %t98 = load ptr, ptr %t97, align 8
  %t99 = getelementptr inbounds %Type, ptr %t98, i32 0, i32 0
  %t100 = load i32, ptr %t99, align 4
  %t101 = load ptr, ptr %b.addr.20, align 8
  %t102 = getelementptr inbounds %Val, ptr %t101, i32 0, i32 0
  %t103 = load ptr, ptr %t102, align 8
  %t104 = getelementptr inbounds %Type, ptr %t103, i32 0, i32 0
  %t105 = load i32, ptr %t104, align 4
  %t106 = icmp ne i32 %t100, %t105
  br i1 %t106, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t107 = load ptr, ptr %cc.addr.0, align 8
  %t108 = getelementptr inbounds %Node, ptr %t107, i32 0, i32 1
  %t109 = load i32, ptr %t108, align 4
  %t110 = getelementptr inbounds [25 x i8], ptr @.str.163, i64 0, i64 0
  %t111 = load ptr, ptr %bop.addr.2, align 8
  %t112 = getelementptr inbounds %BinOp, ptr %t111, i32 0, i32 0
  %t113 = load ptr, ptr %t112, align 8
  %t114 = call ptr @fmt-s(ptr %t110, ptr %t113)
  call void @die-at(i32 %t109, ptr %t114)
  br label %cond.end7
cond.end7:
  %t116 = call ptr @new-tmp()
  store ptr %t116, ptr %tmp.addr.115, align 8
  %t118 = load ptr, ptr %bop.addr.2, align 8
  %t119 = getelementptr inbounds %BinOp, ptr %t118, i32 0, i32 1
  %t120 = load ptr, ptr %t119, align 8
  store ptr %t120, ptr %instr.addr.117, align 8
  %t121 = load ptr, ptr %a.addr.15, align 8
  %t122 = getelementptr inbounds %Val, ptr %t121, i32 0, i32 0
  %t123 = load ptr, ptr %t122, align 8
  %t124 = call i32 @is-unsigned(ptr %t123)
  %t125 = icmp ne i32 %t124, 0
  br i1 %t125, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t126 = load ptr, ptr %bop.addr.2, align 8
  %t127 = getelementptr inbounds %BinOp, ptr %t126, i32 0, i32 2
  %t128 = load ptr, ptr %t127, align 8
  store ptr %t128, ptr %instr.addr.117, align 8
  br label %cond.end8
cond.end8:
  %t129 = load ptr, ptr @g-body-stream, align 8
  %t130 = getelementptr inbounds [21 x i8], ptr @.str.164, i64 0, i64 0
  %t131 = load ptr, ptr %tmp.addr.115, align 8
  %t132 = load ptr, ptr %instr.addr.117, align 8
  %t133 = load ptr, ptr %a.addr.15, align 8
  %t134 = getelementptr inbounds %Val, ptr %t133, i32 0, i32 0
  %t135 = load ptr, ptr %t134, align 8
  %t136 = call ptr @type-to-ir(ptr %t135)
  %t137 = load ptr, ptr %a.addr.15, align 8
  %t138 = getelementptr inbounds %Val, ptr %t137, i32 0, i32 1
  %t139 = load ptr, ptr %t138, align 8
  %t140 = load ptr, ptr %b.addr.20, align 8
  %t141 = getelementptr inbounds %Val, ptr %t140, i32 0, i32 1
  %t142 = load ptr, ptr %t141, align 8
  %t143 = call i32 (ptr, ptr, ...) @fprintf(ptr %t129, ptr %t130, ptr %t131, ptr %t132, ptr %t136, ptr %t139, ptr %t142)
  %t145 = load ptr, ptr %a.addr.15, align 8
  %t146 = getelementptr inbounds %Val, ptr %t145, i32 0, i32 0
  %t147 = load ptr, ptr %t146, align 8
  store ptr %t147, ptr %rtype.addr.144, align 8
  %t148 = load ptr, ptr %bop.addr.2, align 8
  %t149 = getelementptr inbounds %BinOp, ptr %t148, i32 0, i32 3
  %t150 = load i32, ptr %t149, align 4
  %t151 = icmp ne i32 %t150, 0
  br i1 %t151, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t152 = load ptr, ptr @ty-i1, align 8
  store ptr %t152, ptr %rtype.addr.144, align 8
  br label %cond.end9
cond.end9:
  %t153 = load ptr, ptr %rtype.addr.144, align 8
  %t154 = load ptr, ptr %tmp.addr.115, align 8
  %t155 = call ptr @alloc-val(ptr %t153, ptr %t154)
  ret ptr %t155
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
  %and.val9 = alloca i1, align 1
  %and.val11 = alloca i1, align 1
  %tmp.addr.104 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [20 x i8], ptr @.str.165, i64 0, i64 0
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
  %t19 = getelementptr inbounds [35 x i8], ptr @.str.166, i64 0, i64 0
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
  %t63 = load i32, ptr %sw.addr.57, align 4
  %t64 = load i32, ptr %dw.addr.60, align 4
  %t65 = icmp eq i32 %t63, %t64
  br i1 %t65, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t66 = load ptr, ptr %dst.addr.20, align 8
  %t67 = load ptr, ptr %v.addr.28, align 8
  %t68 = getelementptr inbounds %Val, ptr %t67, i32 0, i32 1
  %t69 = load ptr, ptr %t68, align 8
  %t70 = call ptr @alloc-val(ptr %t66, ptr %t69)
  ret ptr %t70
cond.end5:
  %t71 = load i32, ptr %dw.addr.60, align 4
  %t72 = load i32, ptr %sw.addr.57, align 4
  %t73 = icmp slt i32 %t71, %t72
  br i1 %t73, label %cond.then6.0, label %cond.test6.1
cond.then6.0:
  %t74 = getelementptr inbounds [6 x i8], ptr @.str.167, i64 0, i64 0
  store ptr %t74, ptr %instr.addr.49, align 8
  br label %cond.end6
cond.test6.1:
  br i1 1, label %cond.then6.1, label %cond.end6
cond.then6.1:
  %t75 = load ptr, ptr %src.addr.33, align 8
  %t76 = call i32 @is-unsigned(ptr %t75)
  %t77 = icmp ne i32 %t76, 0
  br i1 %t77, label %cond.then7.0, label %cond.test7.1
cond.then7.0:
  %t78 = getelementptr inbounds [5 x i8], ptr @.str.168, i64 0, i64 0
  store ptr %t78, ptr %instr.addr.49, align 8
  br label %cond.end7
cond.test7.1:
  br i1 1, label %cond.then7.1, label %cond.end7
cond.then7.1:
  %t79 = getelementptr inbounds [5 x i8], ptr @.str.169, i64 0, i64 0
  store ptr %t79, ptr %instr.addr.49, align 8
  br label %cond.end7
cond.end7:
  br label %cond.end6
cond.end6:
  br label %cond.end3
cond.end3:
  %t80 = load ptr, ptr %src.addr.33, align 8
  %t81 = call i32 @is-int-type(ptr %t80)
  %t82 = icmp ne i32 %t81, 0
  store i1 %t82, ptr %and.val9, align 1
  br i1 %t82, label %and.rhs9, label %and.end9
and.rhs9:
  %t83 = load ptr, ptr %dst.addr.20, align 8
  %t84 = getelementptr inbounds %Type, ptr %t83, i32 0, i32 0
  %t85 = load i32, ptr %t84, align 4
  %t86 = icmp eq i32 %t85, 10
  store i1 %t86, ptr %and.val9, align 1
  br label %and.end9
and.end9:
  %t87 = load i1, ptr %and.val9, align 1
  br i1 %t87, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t88 = getelementptr inbounds [9 x i8], ptr @.str.170, i64 0, i64 0
  store ptr %t88, ptr %instr.addr.49, align 8
  br label %cond.end8
cond.end8:
  %t89 = load ptr, ptr %src.addr.33, align 8
  %t90 = getelementptr inbounds %Type, ptr %t89, i32 0, i32 0
  %t91 = load i32, ptr %t90, align 4
  %t92 = icmp eq i32 %t91, 10
  store i1 %t92, ptr %and.val11, align 1
  br i1 %t92, label %and.rhs11, label %and.end11
and.rhs11:
  %t93 = load ptr, ptr %dst.addr.20, align 8
  %t94 = call i32 @is-int-type(ptr %t93)
  %t95 = icmp ne i32 %t94, 0
  store i1 %t95, ptr %and.val11, align 1
  br label %and.end11
and.end11:
  %t96 = load i1, ptr %and.val11, align 1
  br i1 %t96, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t97 = getelementptr inbounds [9 x i8], ptr @.str.171, i64 0, i64 0
  store ptr %t97, ptr %instr.addr.49, align 8
  br label %cond.end10
cond.end10:
  %t98 = load ptr, ptr %instr.addr.49, align 8
  %t99 = icmp eq ptr %t98, null
  br i1 %t99, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t100 = load ptr, ptr %cc.addr.0, align 8
  %t101 = getelementptr inbounds %Node, ptr %t100, i32 0, i32 1
  %t102 = load i32, ptr %t101, align 4
  %t103 = getelementptr inbounds [29 x i8], ptr @.str.172, i64 0, i64 0
  call void @die-at(i32 %t102, ptr %t103)
  br label %cond.end12
cond.end12:
  %t105 = call ptr @new-tmp()
  store ptr %t105, ptr %tmp.addr.104, align 8
  %t106 = load ptr, ptr @g-body-stream, align 8
  %t107 = getelementptr inbounds [23 x i8], ptr @.str.173, i64 0, i64 0
  %t108 = load ptr, ptr %tmp.addr.104, align 8
  %t109 = load ptr, ptr %instr.addr.49, align 8
  %t110 = load ptr, ptr %src.addr.33, align 8
  %t111 = call ptr @type-to-ir(ptr %t110)
  %t112 = load ptr, ptr %v.addr.28, align 8
  %t113 = getelementptr inbounds %Val, ptr %t112, i32 0, i32 1
  %t114 = load ptr, ptr %t113, align 8
  %t115 = load ptr, ptr %dst.addr.20, align 8
  %t116 = call ptr @type-to-ir(ptr %t115)
  %t117 = call i32 (ptr, ptr, ...) @fprintf(ptr %t106, ptr %t107, ptr %t108, ptr %t109, ptr %t111, ptr %t114, ptr %t116)
  %t118 = load ptr, ptr %dst.addr.20, align 8
  %t119 = load ptr, ptr %tmp.addr.104, align 8
  %t120 = call ptr @alloc-val(ptr %t118, ptr %t119)
  ret ptr %t120
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
  %t8 = getelementptr inbounds [17 x i8], ptr @.str.174, i64 0, i64 0
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
  %t21 = icmp ne i32 %t20, 10
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
  %t32 = icmp ne i32 %t31, 12
  store i1 %t32, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t33 = load i1, ptr %or.val2, align 1
  br i1 %t33, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t34 = load ptr, ptr %cc.addr.0, align 8
  %t35 = getelementptr inbounds %Node, ptr %t34, i32 0, i32 1
  %t36 = load i32, ptr %t35, align 4
  %t37 = getelementptr inbounds [37 x i8], ptr @.str.175, i64 0, i64 0
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
  %t48 = getelementptr inbounds [29 x i8], ptr @.str.176, i64 0, i64 0
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
  %t85 = getelementptr inbounds [32 x i8], ptr @.str.177, i64 0, i64 0
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
  %t104 = getelementptr inbounds [59 x i8], ptr @.str.178, i64 0, i64 0
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
  %t117 = getelementptr inbounds [34 x i8], ptr @.str.179, i64 0, i64 0
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
  %coerced.addr.106 = alloca ptr, align 8
  %cv.addr.123 = alloca ptr, align 8
  %gep.addr.125 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [21 x i8], ptr @.str.180, i64 0, i64 0
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
  %t21 = icmp ne i32 %t20, 10
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
  %t32 = icmp ne i32 %t31, 12
  store i1 %t32, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t33 = load i1, ptr %or.val2, align 1
  br i1 %t33, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t34 = load ptr, ptr %cc.addr.0, align 8
  %t35 = getelementptr inbounds %Node, ptr %t34, i32 0, i32 1
  %t36 = load i32, ptr %t35, align 4
  %t37 = getelementptr inbounds [41 x i8], ptr @.str.181, i64 0, i64 0
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
  %t48 = getelementptr inbounds [33 x i8], ptr @.str.182, i64 0, i64 0
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
  %t85 = getelementptr inbounds [36 x i8], ptr @.str.183, i64 0, i64 0
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
  %t107 = load ptr, ptr %v.addr.101, align 8
  %t108 = load ptr, ptr %ftype.addr.93, align 8
  %t109 = load ptr, ptr %cc.addr.0, align 8
  %t110 = getelementptr inbounds %Node, ptr %t109, i32 0, i32 1
  %t111 = load i32, ptr %t110, align 4
  %t112 = call ptr @coerce-int-val(ptr %t107, ptr %t108, i32 %t111)
  store ptr %t112, ptr %coerced.addr.106, align 8
  %t113 = load ptr, ptr %coerced.addr.106, align 8
  %t114 = icmp eq ptr %t113, null
  br i1 %t114, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t115 = load ptr, ptr %cc.addr.0, align 8
  %t116 = getelementptr inbounds %Node, ptr %t115, i32 0, i32 1
  %t117 = load i32, ptr %t116, align 4
  %t118 = getelementptr inbounds [36 x i8], ptr @.str.184, i64 0, i64 0
  %t119 = load ptr, ptr %fn-node.addr.38, align 8
  %t120 = getelementptr inbounds %Node, ptr %t119, i32 0, i32 3
  %t121 = load ptr, ptr %t120, align 8
  %t122 = call ptr @fmt-s(ptr %t118, ptr %t121)
  call void @die-at(i32 %t117, ptr %t122)
  br label %cond.end8
cond.end8:
  %t124 = load ptr, ptr %coerced.addr.106, align 8
  store ptr %t124, ptr %cv.addr.123, align 8
  %t126 = call ptr @new-tmp()
  store ptr %t126, ptr %gep.addr.125, align 8
  %t127 = load ptr, ptr @g-body-stream, align 8
  %t128 = getelementptr inbounds [59 x i8], ptr @.str.185, i64 0, i64 0
  %t129 = load ptr, ptr %gep.addr.125, align 8
  %t130 = load ptr, ptr %sd.addr.49, align 8
  %t131 = getelementptr inbounds %StructDef, ptr %t130, i32 0, i32 0
  %t132 = load ptr, ptr %t131, align 8
  %t133 = load ptr, ptr %p.addr.9, align 8
  %t134 = getelementptr inbounds %Val, ptr %t133, i32 0, i32 1
  %t135 = load ptr, ptr %t134, align 8
  %t136 = load i32, ptr %idx.addr.55, align 4
  %t137 = call i32 (ptr, ptr, ...) @fprintf(ptr %t127, ptr %t128, ptr %t129, ptr %t132, ptr %t135, i32 %t136)
  %t138 = load ptr, ptr @g-body-stream, align 8
  %t139 = getelementptr inbounds [33 x i8], ptr @.str.186, i64 0, i64 0
  %t140 = load ptr, ptr %ftype.addr.93, align 8
  %t141 = call ptr @type-to-ir(ptr %t140)
  %t142 = load ptr, ptr %cv.addr.123, align 8
  %t143 = getelementptr inbounds %Val, ptr %t142, i32 0, i32 1
  %t144 = load ptr, ptr %t143, align 8
  %t145 = load ptr, ptr %gep.addr.125, align 8
  %t146 = load ptr, ptr %ftype.addr.93, align 8
  %t147 = call i32 @type-size(ptr %t146)
  %t148 = call i32 (ptr, ptr, ...) @fprintf(ptr %t138, ptr %t139, ptr %t141, ptr %t144, ptr %t145, i32 %t147)
  %t149 = load ptr, ptr @ty-void, align 8
  %t150 = call ptr @alloc-val(ptr %t149, ptr null)
  ret ptr %t150
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
  %t8 = getelementptr inbounds [21 x i8], ptr @.str.187, i64 0, i64 0
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
  %t19 = getelementptr inbounds [30 x i8], ptr @.str.188, i64 0, i64 0
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
  %t31 = getelementptr inbounds [42 x i8], ptr @.str.189, i64 0, i64 0
  %t32 = load ptr, ptr %gep.addr.28, align 8
  %t33 = load ptr, ptr %ty.addr.20, align 8
  %t34 = call ptr @type-to-ir(ptr %t33)
  %t35 = call i32 (ptr, ptr, ...) @fprintf(ptr %t30, ptr %t31, ptr %t32, ptr %t34)
  %t37 = call ptr @new-tmp()
  store ptr %t37, ptr %sz.addr.36, align 8
  %t38 = load ptr, ptr @g-body-stream, align 8
  %t39 = getelementptr inbounds [31 x i8], ptr @.str.190, i64 0, i64 0
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
  %t12 = getelementptr inbounds [27 x i8], ptr @.str.191, i64 0, i64 0
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
  %t23 = getelementptr inbounds [36 x i8], ptr @.str.192, i64 0, i64 0
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
  %t35 = call ptr @make-type(i32 10)
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
  %t48 = getelementptr inbounds [36 x i8], ptr @.str.193, i64 0, i64 0
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
  %t59 = getelementptr inbounds [28 x i8], ptr @.str.194, i64 0, i64 0
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
  %t8 = getelementptr inbounds [20 x i8], ptr @.str.195, i64 0, i64 0
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
  %t19 = icmp ne i32 %t18, 10
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
  %t30 = getelementptr inbounds [36 x i8], ptr @.str.196, i64 0, i64 0
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
  %t44 = getelementptr inbounds [28 x i8], ptr @.str.197, i64 0, i64 0
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
  %t58 = getelementptr inbounds [26 x i8], ptr @.str.198, i64 0, i64 0
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
  %t78 = getelementptr inbounds [50 x i8], ptr @.str.199, i64 0, i64 0
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
  %t90 = getelementptr inbounds [34 x i8], ptr @.str.200, i64 0, i64 0
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
  %coerced.addr.80 = alloca ptr, align 8
  %cv.addr.93 = alloca ptr, align 8
  %gep.addr.95 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [21 x i8], ptr @.str.201, i64 0, i64 0
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
  %t19 = icmp ne i32 %t18, 10
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
  %t30 = getelementptr inbounds [37 x i8], ptr @.str.202, i64 0, i64 0
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
  %t44 = getelementptr inbounds [29 x i8], ptr @.str.203, i64 0, i64 0
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
  %t58 = getelementptr inbounds [26 x i8], ptr @.str.204, i64 0, i64 0
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
  %t81 = load ptr, ptr %v.addr.75, align 8
  %t82 = load ptr, ptr %elem.addr.69, align 8
  %t83 = load ptr, ptr %cc.addr.0, align 8
  %t84 = getelementptr inbounds %Node, ptr %t83, i32 0, i32 1
  %t85 = load i32, ptr %t84, align 4
  %t86 = call ptr @coerce-int-val(ptr %t81, ptr %t82, i32 %t85)
  store ptr %t86, ptr %coerced.addr.80, align 8
  %t87 = load ptr, ptr %coerced.addr.80, align 8
  %t88 = icmp eq ptr %t87, null
  br i1 %t88, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t89 = load ptr, ptr %cc.addr.0, align 8
  %t90 = getelementptr inbounds %Node, ptr %t89, i32 0, i32 1
  %t91 = load i32, ptr %t90, align 4
  %t92 = getelementptr inbounds [27 x i8], ptr @.str.205, i64 0, i64 0
  call void @die-at(i32 %t91, ptr %t92)
  br label %cond.end5
cond.end5:
  %t94 = load ptr, ptr %coerced.addr.80, align 8
  store ptr %t94, ptr %cv.addr.93, align 8
  %t96 = call ptr @new-tmp()
  store ptr %t96, ptr %gep.addr.95, align 8
  %t97 = load ptr, ptr @g-body-stream, align 8
  %t98 = getelementptr inbounds [50 x i8], ptr @.str.206, i64 0, i64 0
  %t99 = load ptr, ptr %gep.addr.95, align 8
  %t100 = load ptr, ptr %elem.addr.69, align 8
  %t101 = call ptr @type-to-ir(ptr %t100)
  %t102 = load ptr, ptr %p.addr.9, align 8
  %t103 = getelementptr inbounds %Val, ptr %t102, i32 0, i32 1
  %t104 = load ptr, ptr %t103, align 8
  %t105 = load ptr, ptr %idx64.addr.45, align 8
  %t106 = call i32 (ptr, ptr, ...) @fprintf(ptr %t97, ptr %t98, ptr %t99, ptr %t101, ptr %t104, ptr %t105)
  %t107 = load ptr, ptr @g-body-stream, align 8
  %t108 = getelementptr inbounds [33 x i8], ptr @.str.207, i64 0, i64 0
  %t109 = load ptr, ptr %elem.addr.69, align 8
  %t110 = call ptr @type-to-ir(ptr %t109)
  %t111 = load ptr, ptr %cv.addr.93, align 8
  %t112 = getelementptr inbounds %Val, ptr %t111, i32 0, i32 1
  %t113 = load ptr, ptr %t112, align 8
  %t114 = load ptr, ptr %gep.addr.95, align 8
  %t115 = load ptr, ptr %elem.addr.69, align 8
  %t116 = call i32 @type-size(ptr %t115)
  %t117 = call i32 (ptr, ptr, ...) @fprintf(ptr %t107, ptr %t108, ptr %t110, ptr %t113, ptr %t114, i32 %t116)
  %t118 = load ptr, ptr @ty-void, align 8
  %t119 = call ptr @alloc-val(ptr %t118, ptr null)
  ret ptr %t119
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
  %t8 = getelementptr inbounds [19 x i8], ptr @.str.208, i64 0, i64 0
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
  %t26 = getelementptr inbounds [37 x i8], ptr @.str.209, i64 0, i64 0
  call void @die-at(i32 %t25, ptr %t26)
  br label %cond.end1
cond.end1:
  %t27 = load ptr, ptr @ty-i8, align 8
  %t28 = getelementptr inbounds [3 x i8], ptr @.str.210, i64 0, i64 0
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
  %t8 = getelementptr inbounds [22 x i8], ptr @.str.211, i64 0, i64 0
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
  %t19 = getelementptr inbounds [31 x i8], ptr @.str.212, i64 0, i64 0
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
  %t31 = getelementptr inbounds [24 x i8], ptr @.str.213, i64 0, i64 0
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
  %t41 = icmp eq i32 %t40, 11
  br i1 %t41, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t42 = load ptr, ptr %target.addr.9, align 8
  %t43 = getelementptr inbounds %Node, ptr %t42, i32 0, i32 1
  %t44 = load i32, ptr %t43, align 4
  %t45 = getelementptr inbounds [46 x i8], ptr @.str.214, i64 0, i64 0
  %t46 = load ptr, ptr %target.addr.9, align 8
  %t47 = getelementptr inbounds %Node, ptr %t46, i32 0, i32 3
  %t48 = load ptr, ptr %t47, align 8
  %t49 = call ptr @fmt-s(ptr %t45, ptr %t48)
  call void @die-at(i32 %t44, ptr %t49)
  br label %cond.end3
cond.end3:
  %t51 = call ptr @make-type(i32 10)
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
  %t8 = getelementptr inbounds [27 x i8], ptr @.str.215, i64 0, i64 0
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
  %t19 = icmp ne i32 %t18, 10
  br i1 %t19, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t20 = load ptr, ptr %cc.addr.0, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 1
  %t22 = load i32, ptr %t21, align 4
  %t23 = getelementptr inbounds [30 x i8], ptr @.str.216, i64 0, i64 0
  call void @die-at(i32 %t22, ptr %t23)
  br label %cond.end1
cond.end1:
  %t24 = load ptr, ptr @g-body-stream, align 8
  %t25 = getelementptr inbounds [18 x i8], ptr @.str.217, i64 0, i64 0
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
  %t8 = getelementptr inbounds [29 x i8], ptr @.str.218, i64 0, i64 0
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
  %t24 = icmp ne i32 %t23, 10
  br i1 %t24, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t25 = load ptr, ptr %cc.addr.0, align 8
  %t26 = getelementptr inbounds %Node, ptr %t25, i32 0, i32 1
  %t27 = load i32, ptr %t26, align 4
  %t28 = getelementptr inbounds [30 x i8], ptr @.str.219, i64 0, i64 0
  call void @die-at(i32 %t27, ptr %t28)
  br label %cond.end1
cond.end1:
  %t29 = load ptr, ptr %arg.addr.14, align 8
  %t30 = getelementptr inbounds %Val, ptr %t29, i32 0, i32 0
  %t31 = load ptr, ptr %t30, align 8
  %t32 = getelementptr inbounds %Type, ptr %t31, i32 0, i32 0
  %t33 = load i32, ptr %t32, align 4
  %t34 = icmp ne i32 %t33, 10
  br i1 %t34, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t35 = load ptr, ptr %cc.addr.0, align 8
  %t36 = getelementptr inbounds %Node, ptr %t35, i32 0, i32 1
  %t37 = load i32, ptr %t36, align 4
  %t38 = getelementptr inbounds [31 x i8], ptr @.str.220, i64 0, i64 0
  call void @die-at(i32 %t37, ptr %t38)
  br label %cond.end2
cond.end2:
  %t40 = call ptr @new-tmp()
  store ptr %t40, ptr %tmp.addr.39, align 8
  %t41 = load ptr, ptr @g-body-stream, align 8
  %t42 = getelementptr inbounds [28 x i8], ptr @.str.221, i64 0, i64 0
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

define ptr @emit-funcall-ptr-i32(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %fn.addr.9 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [30 x i8], ptr @.str.222, i64 0, i64 0
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
  %t19 = icmp ne i32 %t18, 10
  br i1 %t19, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t20 = load ptr, ptr %cc.addr.0, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 1
  %t22 = load i32, ptr %t21, align 4
  %t23 = getelementptr inbounds [33 x i8], ptr @.str.223, i64 0, i64 0
  call void @die-at(i32 %t22, ptr %t23)
  br label %cond.end1
cond.end1:
  %t25 = call ptr @new-tmp()
  store ptr %t25, ptr %tmp.addr.24, align 8
  %t26 = load ptr, ptr @g-body-stream, align 8
  %t27 = getelementptr inbounds [22 x i8], ptr @.str.224, i64 0, i64 0
  %t28 = load ptr, ptr %tmp.addr.24, align 8
  %t29 = load ptr, ptr %fn.addr.9, align 8
  %t30 = getelementptr inbounds %Val, ptr %t29, i32 0, i32 1
  %t31 = load ptr, ptr %t30, align 8
  %t32 = call i32 (ptr, ptr, ...) @fprintf(ptr %t26, ptr %t27, ptr %t28, ptr %t31)
  %t33 = load ptr, ptr @ty-i32, align 8
  %t34 = load ptr, ptr %tmp.addr.24, align 8
  %t35 = call ptr @alloc-val(ptr %t33, ptr %t34)
  ret ptr %t35
}

define ptr @emit-funcall-ptr-i64(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %fn.addr.9 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [30 x i8], ptr @.str.225, i64 0, i64 0
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
  %t19 = icmp ne i32 %t18, 10
  br i1 %t19, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t20 = load ptr, ptr %cc.addr.0, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 1
  %t22 = load i32, ptr %t21, align 4
  %t23 = getelementptr inbounds [33 x i8], ptr @.str.226, i64 0, i64 0
  call void @die-at(i32 %t22, ptr %t23)
  br label %cond.end1
cond.end1:
  %t25 = call ptr @new-tmp()
  store ptr %t25, ptr %tmp.addr.24, align 8
  %t26 = load ptr, ptr @g-body-stream, align 8
  %t27 = getelementptr inbounds [22 x i8], ptr @.str.227, i64 0, i64 0
  %t28 = load ptr, ptr %tmp.addr.24, align 8
  %t29 = load ptr, ptr %fn.addr.9, align 8
  %t30 = getelementptr inbounds %Val, ptr %t29, i32 0, i32 1
  %t31 = load ptr, ptr %t30, align 8
  %t32 = call i32 (ptr, ptr, ...) @fprintf(ptr %t26, ptr %t27, ptr %t28, ptr %t31)
  %t33 = load ptr, ptr @ty-i64, align 8
  %t34 = load ptr, ptr %tmp.addr.24, align 8
  %t35 = call ptr @alloc-val(ptr %t33, ptr %t34)
  ret ptr %t35
}

define ptr @emit-funcall-ptr-ptr(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %fn.addr.9 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [30 x i8], ptr @.str.228, i64 0, i64 0
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
  %t19 = icmp ne i32 %t18, 10
  br i1 %t19, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t20 = load ptr, ptr %cc.addr.0, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 1
  %t22 = load i32, ptr %t21, align 4
  %t23 = getelementptr inbounds [33 x i8], ptr @.str.229, i64 0, i64 0
  call void @die-at(i32 %t22, ptr %t23)
  br label %cond.end1
cond.end1:
  %t25 = call ptr @new-tmp()
  store ptr %t25, ptr %tmp.addr.24, align 8
  %t26 = load ptr, ptr @g-body-stream, align 8
  %t27 = getelementptr inbounds [22 x i8], ptr @.str.230, i64 0, i64 0
  %t28 = load ptr, ptr %tmp.addr.24, align 8
  %t29 = load ptr, ptr %fn.addr.9, align 8
  %t30 = getelementptr inbounds %Val, ptr %t29, i32 0, i32 1
  %t31 = load ptr, ptr %t30, align 8
  %t32 = call i32 (ptr, ptr, ...) @fprintf(ptr %t26, ptr %t27, ptr %t28, ptr %t31)
  %t33 = load ptr, ptr @ty-ptr, align 8
  %t34 = load ptr, ptr %tmp.addr.24, align 8
  %t35 = call ptr @alloc-val(ptr %t33, ptr %t34)
  ret ptr %t35
}

define ptr @emit-funcall(ptr %call.arg, ptr %scope.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %scope.addr = alloca ptr, align 8
  store ptr %scope.arg, ptr %scope.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %fn-val.addr.9 = alloca ptr, align 8
  %fn-type.addr.14 = alloca ptr, align 8
  %ret-type.addr.26 = alloca ptr, align 8
  %np.addr.30 = alloca i32, align 4
  %nargs.addr.34 = alloca i32, align 4
  %arg-vals.addr.50 = alloca ptr, align 8
  %i.addr.56 = alloca i32, align 4
  %ret-ir.addr.72 = alloca ptr, align 8
  %av.addr.93 = alloca ptr, align 8
  %tmp.addr.116 = alloca ptr, align 8
  %av.addr.134 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [31 x i8], ptr @.str.231, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  %t12 = load ptr, ptr %scope.addr, align 8
  %t13 = call ptr @emit-node(ptr %t11, ptr %t12)
  store ptr %t13, ptr %fn-val.addr.9, align 8
  %t15 = load ptr, ptr %fn-val.addr.9, align 8
  %t16 = getelementptr inbounds %Val, ptr %t15, i32 0, i32 0
  %t17 = load ptr, ptr %t16, align 8
  store ptr %t17, ptr %fn-type.addr.14, align 8
  %t18 = load ptr, ptr %fn-type.addr.14, align 8
  %t19 = getelementptr inbounds %Type, ptr %t18, i32 0, i32 0
  %t20 = load i32, ptr %t19, align 4
  %t21 = icmp ne i32 %t20, 11
  br i1 %t21, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t22 = load ptr, ptr %cc.addr.0, align 8
  %t23 = getelementptr inbounds %Node, ptr %t22, i32 0, i32 1
  %t24 = load i32, ptr %t23, align 4
  %t25 = getelementptr inbounds [46 x i8], ptr @.str.232, i64 0, i64 0
  call void @die-at(i32 %t24, ptr %t25)
  br label %cond.end1
cond.end1:
  %t27 = load ptr, ptr %fn-type.addr.14, align 8
  %t28 = getelementptr inbounds %Type, ptr %t27, i32 0, i32 1
  %t29 = load ptr, ptr %t28, align 8
  store ptr %t29, ptr %ret-type.addr.26, align 8
  %t31 = load ptr, ptr %fn-type.addr.14, align 8
  %t32 = getelementptr inbounds %Type, ptr %t31, i32 0, i32 3
  %t33 = load i32, ptr %t32, align 4
  store i32 %t33, ptr %np.addr.30, align 4
  %t35 = load ptr, ptr %cc.addr.0, align 8
  %t36 = call i32 @node-len(ptr %t35)
  %t37 = sub nsw i32 %t36, 2
  store i32 %t37, ptr %nargs.addr.34, align 4
  %t38 = load i32, ptr %nargs.addr.34, align 4
  %t39 = load i32, ptr %np.addr.30, align 4
  %t40 = icmp ne i32 %t38, %t39
  br i1 %t40, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t41 = load ptr, ptr %cc.addr.0, align 8
  %t42 = getelementptr inbounds %Node, ptr %t41, i32 0, i32 1
  %t43 = load i32, ptr %t42, align 4
  %t44 = getelementptr inbounds [34 x i8], ptr @.str.233, i64 0, i64 0
  %t45 = load i32, ptr %np.addr.30, align 4
  %t46 = sext i32 %t45 to i64
  %t47 = load i32, ptr %nargs.addr.34, align 4
  %t48 = sext i32 %t47 to i64
  %t49 = call ptr @fmt-s(ptr %t44, i64 %t46, i64 %t48)
  call void @die-at(i32 %t43, ptr %t49)
  br label %cond.end2
cond.end2:
  %t51 = load i32, ptr %nargs.addr.34, align 4
  %t52 = sext i32 %t51 to i64
  %t53 = sext i32 8 to i64
  %t54 = mul nsw i64 %t52, %t53
  %t55 = call ptr @arena-alloc(i64 %t54)
  store ptr %t55, ptr %arg-vals.addr.50, align 8
  store i32 0, ptr %i.addr.56, align 4
  br label %while.cond3
while.cond3:
  %t57 = load i32, ptr %i.addr.56, align 4
  %t58 = load i32, ptr %nargs.addr.34, align 4
  %t59 = icmp slt i32 %t57, %t58
  br i1 %t59, label %while.body3, label %while.end3
while.body3:
  %t60 = load ptr, ptr %arg-vals.addr.50, align 8
  %t61 = load i32, ptr %i.addr.56, align 4
  %t62 = sext i32 %t61 to i64
  %t63 = load ptr, ptr %cc.addr.0, align 8
  %t64 = load i32, ptr %i.addr.56, align 4
  %t65 = add nsw i32 %t64, 2
  %t66 = call ptr @node-at(ptr %t63, i32 %t65)
  %t67 = load ptr, ptr %scope.addr, align 8
  %t68 = call ptr @emit-node(ptr %t66, ptr %t67)
  %t69 = getelementptr inbounds ptr, ptr %t60, i64 %t62
  store ptr %t68, ptr %t69, align 8
  %t70 = load i32, ptr %i.addr.56, align 4
  %t71 = add nsw i32 %t70, 1
  store i32 %t71, ptr %i.addr.56, align 4
  br label %while.cond3
while.end3:
  %t73 = load ptr, ptr %ret-type.addr.26, align 8
  %t74 = call ptr @type-to-ir(ptr %t73)
  store ptr %t74, ptr %ret-ir.addr.72, align 8
  %t75 = load ptr, ptr %ret-type.addr.26, align 8
  %t76 = getelementptr inbounds %Type, ptr %t75, i32 0, i32 0
  %t77 = load i32, ptr %t76, align 4
  %t78 = icmp eq i32 %t77, 0
  br i1 %t78, label %cond.then4.0, label %cond.test4.1
cond.then4.0:
  %t79 = load ptr, ptr @g-body-stream, align 8
  %t80 = getelementptr inbounds [16 x i8], ptr @.str.234, i64 0, i64 0
  %t81 = load ptr, ptr %fn-val.addr.9, align 8
  %t82 = getelementptr inbounds %Val, ptr %t81, i32 0, i32 1
  %t83 = load ptr, ptr %t82, align 8
  %t84 = call i32 (ptr, ptr, ...) @fprintf(ptr %t79, ptr %t80, ptr %t83)
  store i32 0, ptr %i.addr.56, align 4
  br label %while.cond5
while.cond5:
  %t85 = load i32, ptr %i.addr.56, align 4
  %t86 = load i32, ptr %nargs.addr.34, align 4
  %t87 = icmp slt i32 %t85, %t86
  br i1 %t87, label %while.body5, label %while.end5
while.body5:
  %t88 = load i32, ptr %i.addr.56, align 4
  %t89 = icmp ne i32 %t88, 0
  br i1 %t89, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t90 = load ptr, ptr @g-body-stream, align 8
  %t91 = getelementptr inbounds [3 x i8], ptr @.str.235, i64 0, i64 0
  %t92 = call i32 (ptr, ptr, ...) @fprintf(ptr %t90, ptr %t91)
  br label %cond.end6
cond.end6:
  %t94 = load ptr, ptr %arg-vals.addr.50, align 8
  %t95 = load i32, ptr %i.addr.56, align 4
  %t96 = sext i32 %t95 to i64
  %t97 = getelementptr inbounds ptr, ptr %t94, i64 %t96
  %t98 = load ptr, ptr %t97, align 8
  store ptr %t98, ptr %av.addr.93, align 8
  %t99 = load ptr, ptr @g-body-stream, align 8
  %t100 = getelementptr inbounds [6 x i8], ptr @.str.236, i64 0, i64 0
  %t101 = load ptr, ptr %av.addr.93, align 8
  %t102 = getelementptr inbounds %Val, ptr %t101, i32 0, i32 0
  %t103 = load ptr, ptr %t102, align 8
  %t104 = call ptr @type-to-ir(ptr %t103)
  %t105 = load ptr, ptr %av.addr.93, align 8
  %t106 = getelementptr inbounds %Val, ptr %t105, i32 0, i32 1
  %t107 = load ptr, ptr %t106, align 8
  %t108 = call i32 (ptr, ptr, ...) @fprintf(ptr %t99, ptr %t100, ptr %t104, ptr %t107)
  %t109 = load i32, ptr %i.addr.56, align 4
  %t110 = add nsw i32 %t109, 1
  store i32 %t110, ptr %i.addr.56, align 4
  br label %while.cond5
while.end5:
  %t111 = load ptr, ptr @g-body-stream, align 8
  %t112 = getelementptr inbounds [3 x i8], ptr @.str.237, i64 0, i64 0
  %t113 = call i32 (ptr, ptr, ...) @fprintf(ptr %t111, ptr %t112)
  %t114 = load ptr, ptr @ty-void, align 8
  %t115 = call ptr @alloc-val(ptr %t114, ptr null)
  ret ptr %t115
cond.test4.1:
  br i1 1, label %cond.then4.1, label %cond.end4
cond.then4.1:
  %t117 = call ptr @new-tmp()
  store ptr %t117, ptr %tmp.addr.116, align 8
  %t118 = load ptr, ptr @g-body-stream, align 8
  %t119 = getelementptr inbounds [19 x i8], ptr @.str.238, i64 0, i64 0
  %t120 = load ptr, ptr %tmp.addr.116, align 8
  %t121 = load ptr, ptr %ret-ir.addr.72, align 8
  %t122 = load ptr, ptr %fn-val.addr.9, align 8
  %t123 = getelementptr inbounds %Val, ptr %t122, i32 0, i32 1
  %t124 = load ptr, ptr %t123, align 8
  %t125 = call i32 (ptr, ptr, ...) @fprintf(ptr %t118, ptr %t119, ptr %t120, ptr %t121, ptr %t124)
  store i32 0, ptr %i.addr.56, align 4
  br label %while.cond7
while.cond7:
  %t126 = load i32, ptr %i.addr.56, align 4
  %t127 = load i32, ptr %nargs.addr.34, align 4
  %t128 = icmp slt i32 %t126, %t127
  br i1 %t128, label %while.body7, label %while.end7
while.body7:
  %t129 = load i32, ptr %i.addr.56, align 4
  %t130 = icmp ne i32 %t129, 0
  br i1 %t130, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t131 = load ptr, ptr @g-body-stream, align 8
  %t132 = getelementptr inbounds [3 x i8], ptr @.str.239, i64 0, i64 0
  %t133 = call i32 (ptr, ptr, ...) @fprintf(ptr %t131, ptr %t132)
  br label %cond.end8
cond.end8:
  %t135 = load ptr, ptr %arg-vals.addr.50, align 8
  %t136 = load i32, ptr %i.addr.56, align 4
  %t137 = sext i32 %t136 to i64
  %t138 = getelementptr inbounds ptr, ptr %t135, i64 %t137
  %t139 = load ptr, ptr %t138, align 8
  store ptr %t139, ptr %av.addr.134, align 8
  %t140 = load ptr, ptr @g-body-stream, align 8
  %t141 = getelementptr inbounds [6 x i8], ptr @.str.240, i64 0, i64 0
  %t142 = load ptr, ptr %av.addr.134, align 8
  %t143 = getelementptr inbounds %Val, ptr %t142, i32 0, i32 0
  %t144 = load ptr, ptr %t143, align 8
  %t145 = call ptr @type-to-ir(ptr %t144)
  %t146 = load ptr, ptr %av.addr.134, align 8
  %t147 = getelementptr inbounds %Val, ptr %t146, i32 0, i32 1
  %t148 = load ptr, ptr %t147, align 8
  %t149 = call i32 (ptr, ptr, ...) @fprintf(ptr %t140, ptr %t141, ptr %t145, ptr %t148)
  %t150 = load i32, ptr %i.addr.56, align 4
  %t151 = add nsw i32 %t150, 1
  store i32 %t151, ptr %i.addr.56, align 4
  br label %while.cond7
while.end7:
  %t152 = load ptr, ptr @g-body-stream, align 8
  %t153 = getelementptr inbounds [3 x i8], ptr @.str.241, i64 0, i64 0
  %t154 = call i32 (ptr, ptr, ...) @fprintf(ptr %t152, ptr %t153)
  %t155 = load ptr, ptr %ret-type.addr.26, align 8
  %t156 = load ptr, ptr %tmp.addr.116, align 8
  %t157 = call ptr @alloc-val(ptr %t155, ptr %t156)
  ret ptr %t157
cond.end4:
  ret ptr null
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
  %t8 = getelementptr inbounds [20 x i8], ptr @.str.242, i64 0, i64 0
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
  %t19 = icmp ne i32 %t18, 10
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
  %t30 = getelementptr inbounds [37 x i8], ptr @.str.243, i64 0, i64 0
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
  %t40 = getelementptr inbounds [34 x i8], ptr @.str.244, i64 0, i64 0
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
  %coerced.addr.42 = alloca ptr, align 8
  %cv.addr.55 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [24 x i8], ptr @.str.245, i64 0, i64 0
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
  %t19 = icmp ne i32 %t18, 10
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
  %t30 = getelementptr inbounds [40 x i8], ptr @.str.246, i64 0, i64 0
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
  %t43 = load ptr, ptr %v.addr.37, align 8
  %t44 = load ptr, ptr %elem.addr.31, align 8
  %t45 = load ptr, ptr %cc.addr.0, align 8
  %t46 = getelementptr inbounds %Node, ptr %t45, i32 0, i32 1
  %t47 = load i32, ptr %t46, align 4
  %t48 = call ptr @coerce-int-val(ptr %t43, ptr %t44, i32 %t47)
  store ptr %t48, ptr %coerced.addr.42, align 8
  %t49 = load ptr, ptr %coerced.addr.42, align 8
  %t50 = icmp eq ptr %t49, null
  br i1 %t50, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t51 = load ptr, ptr %cc.addr.0, align 8
  %t52 = getelementptr inbounds %Node, ptr %t51, i32 0, i32 1
  %t53 = load i32, ptr %t52, align 4
  %t54 = getelementptr inbounds [30 x i8], ptr @.str.247, i64 0, i64 0
  call void @die-at(i32 %t53, ptr %t54)
  br label %cond.end3
cond.end3:
  %t56 = load ptr, ptr %coerced.addr.42, align 8
  store ptr %t56, ptr %cv.addr.55, align 8
  %t57 = load ptr, ptr @g-body-stream, align 8
  %t58 = getelementptr inbounds [33 x i8], ptr @.str.248, i64 0, i64 0
  %t59 = load ptr, ptr %elem.addr.31, align 8
  %t60 = call ptr @type-to-ir(ptr %t59)
  %t61 = load ptr, ptr %cv.addr.55, align 8
  %t62 = getelementptr inbounds %Val, ptr %t61, i32 0, i32 1
  %t63 = load ptr, ptr %t62, align 8
  %t64 = load ptr, ptr %p.addr.9, align 8
  %t65 = getelementptr inbounds %Val, ptr %t64, i32 0, i32 1
  %t66 = load ptr, ptr %t65, align 8
  %t67 = load ptr, ptr %elem.addr.31, align 8
  %t68 = call i32 @type-size(ptr %t67)
  %t69 = call i32 (ptr, ptr, ...) @fprintf(ptr %t57, ptr %t58, ptr %t60, ptr %t63, ptr %t66, i32 %t68)
  %t70 = load ptr, ptr @ty-void, align 8
  %t71 = call ptr @alloc-val(ptr %t70, ptr null)
  ret ptr %t71
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
  %t8 = getelementptr inbounds [20 x i8], ptr @.str.249, i64 0, i64 0
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
  %t19 = icmp ne i32 %t18, 10
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
  %t30 = getelementptr inbounds [36 x i8], ptr @.str.250, i64 0, i64 0
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
  %t44 = getelementptr inbounds [29 x i8], ptr @.str.251, i64 0, i64 0
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
  %t58 = getelementptr inbounds [26 x i8], ptr @.str.252, i64 0, i64 0
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
  %t78 = getelementptr inbounds [50 x i8], ptr @.str.253, i64 0, i64 0
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
  %t8 = getelementptr inbounds [18 x i8], ptr @.str.254, i64 0, i64 0
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
  %t23 = getelementptr inbounds [23 x i8], ptr @.str.255, i64 0, i64 0
  call void @die-at(i32 %t22, ptr %t23)
  br label %cond.end1
cond.end1:
  %t25 = call ptr @new-tmp()
  store ptr %t25, ptr %tmp.addr.24, align 8
  %t26 = load ptr, ptr @g-body-stream, align 8
  %t27 = getelementptr inbounds [21 x i8], ptr @.str.256, i64 0, i64 0
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
  %t3 = getelementptr inbounds [3 x i8], ptr @.str.257, i64 0, i64 0
  store ptr %t3, ptr %tag.addr.2, align 8
  %t4 = load i32, ptr %is-and.addr, align 4
  %t5 = icmp ne i32 %t4, 0
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t6 = getelementptr inbounds [4 x i8], ptr @.str.258, i64 0, i64 0
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
  %t13 = getelementptr inbounds [18 x i8], ptr @.str.259, i64 0, i64 0
  %t14 = load ptr, ptr %tag.addr.2, align 8
  %t15 = call ptr @fmt-s(ptr %t13, ptr %t14)
  call void @die-at(i32 %t12, ptr %t15)
  br label %cond.end1
cond.end1:
  %t17 = call i32 @new-label-id()
  store i32 %t17, ptr %id.addr.16, align 4
  %t19 = getelementptr inbounds [9 x i8], ptr @.str.260, i64 0, i64 0
  %t20 = load ptr, ptr %tag.addr.2, align 8
  %t21 = load i32, ptr %id.addr.16, align 4
  %t22 = call ptr @fmt-sd(ptr %t19, ptr %t20, i32 %t21)
  store ptr %t22, ptr %rhs-lbl.addr.18, align 8
  %t24 = getelementptr inbounds [9 x i8], ptr @.str.261, i64 0, i64 0
  %t25 = load ptr, ptr %tag.addr.2, align 8
  %t26 = load i32, ptr %id.addr.16, align 4
  %t27 = call ptr @fmt-sd(ptr %t24, ptr %t25, i32 %t26)
  store ptr %t27, ptr %end-lbl.addr.23, align 8
  %t29 = getelementptr inbounds [11 x i8], ptr @.str.262, i64 0, i64 0
  %t30 = load ptr, ptr %tag.addr.2, align 8
  %t31 = load i32, ptr %id.addr.16, align 4
  %t32 = call ptr @fmt-sd(ptr %t29, ptr %t30, i32 %t31)
  store ptr %t32, ptr %slot.addr.28, align 8
  %t33 = load ptr, ptr @g-entry-stream, align 8
  %t34 = getelementptr inbounds [27 x i8], ptr @.str.263, i64 0, i64 0
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
  %t52 = getelementptr inbounds [23 x i8], ptr @.str.264, i64 0, i64 0
  %t53 = load ptr, ptr %tag.addr.2, align 8
  %t54 = call ptr @fmt-s(ptr %t52, ptr %t53)
  call void @die-at(i32 %t51, ptr %t54)
  br label %cond.end2
cond.end2:
  %t55 = load ptr, ptr @g-body-stream, align 8
  %t56 = getelementptr inbounds [32 x i8], ptr @.str.265, i64 0, i64 0
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
  %t65 = getelementptr inbounds [36 x i8], ptr @.str.266, i64 0, i64 0
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
  %t73 = getelementptr inbounds [36 x i8], ptr @.str.267, i64 0, i64 0
  %t74 = load ptr, ptr %lhs.addr.37, align 8
  %t75 = getelementptr inbounds %Val, ptr %t74, i32 0, i32 1
  %t76 = load ptr, ptr %t75, align 8
  %t77 = load ptr, ptr %end-lbl.addr.23, align 8
  %t78 = load ptr, ptr %rhs-lbl.addr.18, align 8
  %t79 = call i32 (ptr, ptr, ...) @fprintf(ptr %t72, ptr %t73, ptr %t76, ptr %t77, ptr %t78)
  br label %cond.end3
cond.end3:
  %t80 = load ptr, ptr @g-body-stream, align 8
  %t81 = getelementptr inbounds [5 x i8], ptr @.str.268, i64 0, i64 0
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
  %t99 = getelementptr inbounds [23 x i8], ptr @.str.269, i64 0, i64 0
  %t100 = load ptr, ptr %tag.addr.2, align 8
  %t101 = call ptr @fmt-s(ptr %t99, ptr %t100)
  call void @die-at(i32 %t98, ptr %t101)
  br label %cond.end4
cond.end4:
  %t102 = load ptr, ptr @g-body-stream, align 8
  %t103 = getelementptr inbounds [32 x i8], ptr @.str.270, i64 0, i64 0
  %t104 = load ptr, ptr %rhs.addr.84, align 8
  %t105 = getelementptr inbounds %Val, ptr %t104, i32 0, i32 1
  %t106 = load ptr, ptr %t105, align 8
  %t107 = load ptr, ptr %slot.addr.28, align 8
  %t108 = call i32 (ptr, ptr, ...) @fprintf(ptr %t102, ptr %t103, ptr %t106, ptr %t107)
  %t109 = load ptr, ptr @g-body-stream, align 8
  %t110 = getelementptr inbounds [17 x i8], ptr @.str.271, i64 0, i64 0
  %t111 = load ptr, ptr %end-lbl.addr.23, align 8
  %t112 = call i32 (ptr, ptr, ...) @fprintf(ptr %t109, ptr %t110, ptr %t111)
  %t113 = load ptr, ptr @g-body-stream, align 8
  %t114 = getelementptr inbounds [5 x i8], ptr @.str.272, i64 0, i64 0
  %t115 = load ptr, ptr %end-lbl.addr.23, align 8
  %t116 = call i32 (ptr, ptr, ...) @fprintf(ptr %t113, ptr %t114, ptr %t115)
  store i32 0, ptr @g-block-term, align 4
  %t118 = call ptr @new-tmp()
  store ptr %t118, ptr %tmp.addr.117, align 8
  %t119 = load ptr, ptr @g-body-stream, align 8
  %t120 = getelementptr inbounds [33 x i8], ptr @.str.273, i64 0, i64 0
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
  %t53 = getelementptr inbounds [1 x i8], ptr @.str.274, i64 0, i64 0
  store ptr %t53, ptr %sep.addr.52, align 8
  %t54 = load i32, ptr %i.addr.15, align 4
  %t55 = icmp ne i32 %t54, 0
  br i1 %t55, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t56 = getelementptr inbounds [3 x i8], ptr @.str.275, i64 0, i64 0
  store ptr %t56, ptr %sep.addr.52, align 8
  br label %cond.end2
cond.end2:
  %t58 = load ptr, ptr %arglist.addr.36, align 8
  %t59 = load i64, ptr %apos.addr.38, align 8
  %t60 = getelementptr inbounds i8, ptr %t58, i64 %t59
  %t61 = sext i32 2048 to i64
  %t62 = load i64, ptr %apos.addr.38, align 8
  %t63 = sub nsw i64 %t61, %t62
  %t64 = getelementptr inbounds [8 x i8], ptr @.str.276, i64 0, i64 0
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
  %t87 = icmp ne i32 %t86, 11
  br i1 %t87, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t88 = load ptr, ptr %cc.addr.0, align 8
  %t89 = getelementptr inbounds %Node, ptr %t88, i32 0, i32 1
  %t90 = load i32, ptr %t89, align 4
  %t91 = getelementptr inbounds [19 x i8], ptr @.str.277, i64 0, i64 0
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
  %t107 = getelementptr inbounds [5 x i8], ptr @.str.278, i64 0, i64 0
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
  %t129 = getelementptr inbounds [1 x i8], ptr @.str.279, i64 0, i64 0
  store ptr %t129, ptr %sep.addr.128, align 8
  %t130 = load i32, ptr %i.addr.15, align 4
  %t131 = icmp ne i32 %t130, 0
  br i1 %t131, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t132 = getelementptr inbounds [3 x i8], ptr @.str.280, i64 0, i64 0
  store ptr %t132, ptr %sep.addr.128, align 8
  br label %cond.end6
cond.end6:
  %t133 = load ptr, ptr %sig.addr.100, align 8
  %t134 = load i64, ptr %sp.addr.102, align 8
  %t135 = getelementptr inbounds i8, ptr %t133, i64 %t134
  %t136 = sext i32 512 to i64
  %t137 = load i64, ptr %sp.addr.102, align 8
  %t138 = sub nsw i64 %t136, %t137
  %t139 = getelementptr inbounds [5 x i8], ptr @.str.281, i64 0, i64 0
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
  %t151 = getelementptr inbounds [1 x i8], ptr @.str.282, i64 0, i64 0
  store ptr %t151, ptr %va-sep.addr.150, align 8
  %t152 = load ptr, ptr %ft.addr.80, align 8
  %t153 = getelementptr inbounds %Type, ptr %t152, i32 0, i32 3
  %t154 = load i32, ptr %t153, align 4
  %t155 = icmp ne i32 %t154, 0
  br i1 %t155, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t156 = getelementptr inbounds [3 x i8], ptr @.str.283, i64 0, i64 0
  store ptr %t156, ptr %va-sep.addr.150, align 8
  br label %cond.end7
cond.end7:
  %t157 = load ptr, ptr %sig.addr.100, align 8
  %t158 = load i64, ptr %sp.addr.102, align 8
  %t159 = getelementptr inbounds i8, ptr %t157, i64 %t158
  %t160 = sext i32 512 to i64
  %t161 = load i64, ptr %sp.addr.102, align 8
  %t162 = sub nsw i64 %t160, %t161
  %t163 = getelementptr inbounds [7 x i8], ptr @.str.284, i64 0, i64 0
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
  %t173 = getelementptr inbounds [18 x i8], ptr @.str.285, i64 0, i64 0
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
  %t183 = getelementptr inbounds [23 x i8], ptr @.str.286, i64 0, i64 0
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
  %t203 = getelementptr inbounds [18 x i8], ptr @.str.287, i64 0, i64 0
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
  %t216 = getelementptr inbounds [23 x i8], ptr @.str.288, i64 0, i64 0
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
  %t6 = getelementptr inbounds [12 x i8], ptr @.str.289, i64 0, i64 0
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
  %t16 = getelementptr inbounds [27 x i8], ptr @.str.290, i64 0, i64 0
  call void @die-at(i32 %t15, ptr %t16)
  br label %cond.end1
cond.end1:
  %t18 = load ptr, ptr %cc.addr.0, align 8
  %t19 = call ptr @node-at(ptr %t18, i32 1)
  %t20 = load ptr, ptr %scope.addr, align 8
  %t21 = call ptr @emit-node(ptr %t19, ptr %t20)
  store ptr %t21, ptr %v.addr.17, align 8
  %t22 = load ptr, ptr @g-body-stream, align 8
  %t23 = getelementptr inbounds [13 x i8], ptr @.str.291, i64 0, i64 0
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
  %name.addr.43 = alloca ptr, align 8
  %ty.addr.44 = alloca ptr, align 8
  %slot.addr.58 = alloca ptr, align 8
  %align.addr.63 = alloca i32, align 4
  %v.addr.75 = alloca ptr, align 8
  %coerced.addr.79 = alloca ptr, align 8
  %cv.addr.94 = alloca ptr, align 8
  %last.addr.113 = alloca ptr, align 8
  %j.addr.116 = alloca i32, align 4
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
  %t14 = getelementptr inbounds [14 x i8], ptr @.str.292, i64 0, i64 0
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
  %t25 = getelementptr inbounds [31 x i8], ptr @.str.293, i64 0, i64 0
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
  store ptr null, ptr %name.addr.43, align 8
  %t45 = load ptr, ptr %bname.addr.34, align 8
  %t46 = load ptr, ptr %bname.addr.34, align 8
  %t47 = getelementptr inbounds %Node, ptr %t46, i32 0, i32 1
  %t48 = load i32, ptr %t47, align 4
  %t49 = call ptr @extract-name-and-type(ptr %t45, ptr %name.addr.43, i32 %t48)
  store ptr %t49, ptr %ty.addr.44, align 8
  %t50 = load ptr, ptr %ty.addr.44, align 8
  %t51 = icmp eq ptr %t50, null
  br i1 %t51, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t52 = load ptr, ptr %bname.addr.34, align 8
  %t53 = getelementptr inbounds %Node, ptr %t52, i32 0, i32 1
  %t54 = load i32, ptr %t53, align 4
  %t55 = getelementptr inbounds [27 x i8], ptr @.str.294, i64 0, i64 0
  %t56 = load ptr, ptr %name.addr.43, align 8
  %t57 = call ptr @fmt-s(ptr %t55, ptr %t56)
  call void @die-at(i32 %t54, ptr %t57)
  br label %cond.end4
cond.end4:
  %t59 = getelementptr inbounds [13 x i8], ptr @.str.295, i64 0, i64 0
  %t60 = load ptr, ptr %name.addr.43, align 8
  %t61 = load i32, ptr @g-tmp, align 4
  %t62 = call ptr @fmt-sd(ptr %t59, ptr %t60, i32 %t61)
  store ptr %t62, ptr %slot.addr.58, align 8
  %t64 = load ptr, ptr %ty.addr.44, align 8
  %t65 = call i32 @type-size(ptr %t64)
  store i32 %t65, ptr %align.addr.63, align 4
  %t66 = load i32, ptr @g-tmp, align 4
  %t67 = add nsw i32 %t66, 1
  store i32 %t67, ptr @g-tmp, align 4
  %t68 = load ptr, ptr @g-entry-stream, align 8
  %t69 = getelementptr inbounds [28 x i8], ptr @.str.296, i64 0, i64 0
  %t70 = load ptr, ptr %slot.addr.58, align 8
  %t71 = load ptr, ptr %ty.addr.44, align 8
  %t72 = call ptr @type-to-ir(ptr %t71)
  %t73 = load i32, ptr %align.addr.63, align 4
  %t74 = call i32 (ptr, ptr, ...) @fprintf(ptr %t68, ptr %t69, ptr %t70, ptr %t72, i32 %t73)
  %t76 = load ptr, ptr %bval-node.addr.38, align 8
  %t77 = load ptr, ptr %inner.addr.26, align 8
  %t78 = call ptr @emit-node(ptr %t76, ptr %t77)
  store ptr %t78, ptr %v.addr.75, align 8
  %t80 = load ptr, ptr %v.addr.75, align 8
  %t81 = load ptr, ptr %ty.addr.44, align 8
  %t82 = load ptr, ptr %bval-node.addr.38, align 8
  %t83 = getelementptr inbounds %Node, ptr %t82, i32 0, i32 1
  %t84 = load i32, ptr %t83, align 4
  %t85 = call ptr @coerce-int-val(ptr %t80, ptr %t81, i32 %t84)
  store ptr %t85, ptr %coerced.addr.79, align 8
  %t86 = load ptr, ptr %coerced.addr.79, align 8
  %t87 = icmp eq ptr %t86, null
  br i1 %t87, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t88 = load ptr, ptr %bval-node.addr.38, align 8
  %t89 = getelementptr inbounds %Node, ptr %t88, i32 0, i32 1
  %t90 = load i32, ptr %t89, align 4
  %t91 = getelementptr inbounds [33 x i8], ptr @.str.297, i64 0, i64 0
  %t92 = load ptr, ptr %name.addr.43, align 8
  %t93 = call ptr @fmt-s(ptr %t91, ptr %t92)
  call void @die-at(i32 %t90, ptr %t93)
  br label %cond.end5
cond.end5:
  %t95 = load ptr, ptr %coerced.addr.79, align 8
  store ptr %t95, ptr %cv.addr.94, align 8
  %t96 = load ptr, ptr @g-body-stream, align 8
  %t97 = getelementptr inbounds [33 x i8], ptr @.str.298, i64 0, i64 0
  %t98 = load ptr, ptr %ty.addr.44, align 8
  %t99 = call ptr @type-to-ir(ptr %t98)
  %t100 = load ptr, ptr %cv.addr.94, align 8
  %t101 = getelementptr inbounds %Val, ptr %t100, i32 0, i32 1
  %t102 = load ptr, ptr %t101, align 8
  %t103 = load ptr, ptr %slot.addr.58, align 8
  %t104 = load i32, ptr %align.addr.63, align 4
  %t105 = call i32 (ptr, ptr, ...) @fprintf(ptr %t96, ptr %t97, ptr %t99, ptr %t102, ptr %t103, i32 %t104)
  %t106 = load ptr, ptr %inner.addr.26, align 8
  %t107 = load ptr, ptr %name.addr.43, align 8
  %t108 = load ptr, ptr %ty.addr.44, align 8
  %t109 = load ptr, ptr %slot.addr.58, align 8
  %t110 = call ptr @scope-define(ptr %t106, ptr %t107, ptr %t108, ptr %t109, i32 1)
  %t111 = load i32, ptr %i.addr.29, align 4
  %t112 = add nsw i32 %t111, 2
  store i32 %t112, ptr %i.addr.29, align 4
  br label %while.cond3
while.end3:
  %t114 = load ptr, ptr @ty-void, align 8
  %t115 = call ptr @alloc-val(ptr %t114, ptr null)
  store ptr %t115, ptr %last.addr.113, align 8
  store i32 2, ptr %j.addr.116, align 4
  br label %while.cond6
while.cond6:
  %t117 = load i32, ptr %j.addr.116, align 4
  %t118 = load ptr, ptr %cc.addr.0, align 8
  %t119 = call i32 @node-len(ptr %t118)
  %t120 = icmp slt i32 %t117, %t119
  br i1 %t120, label %while.body6, label %while.end6
while.body6:
  %t121 = load ptr, ptr %cc.addr.0, align 8
  %t122 = load i32, ptr %j.addr.116, align 4
  %t123 = call ptr @node-at(ptr %t121, i32 %t122)
  %t124 = load ptr, ptr %inner.addr.26, align 8
  %t125 = call ptr @emit-node(ptr %t123, ptr %t124)
  store ptr %t125, ptr %last.addr.113, align 8
  %t126 = load i32, ptr %j.addr.116, align 4
  %t127 = add nsw i32 %t126, 1
  store i32 %t127, ptr %j.addr.116, align 4
  br label %while.cond6
while.end6:
  %t128 = load ptr, ptr %last.addr.113, align 8
  ret ptr %t128
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
  %t15 = getelementptr inbounds [35 x i8], ptr @.str.299, i64 0, i64 0
  call void @die-at(i32 %t14, ptr %t15)
  br label %cond.end0
cond.end0:
  %t17 = load i32, ptr %nargs.addr.2, align 4
  %t18 = sdiv i32 %t17, 2
  store i32 %t18, ptr %npairs.addr.16, align 4
  %t20 = call i32 @new-label-id()
  store i32 %t20, ptr %id.addr.19, align 4
  %t22 = getelementptr inbounds [11 x i8], ptr @.str.300, i64 0, i64 0
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
  %t30 = getelementptr inbounds [15 x i8], ptr @.str.301, i64 0, i64 0
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
  %t40 = getelementptr inbounds [15 x i8], ptr @.str.302, i64 0, i64 0
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
  %t66 = getelementptr inbounds [22 x i8], ptr @.str.303, i64 0, i64 0
  call void @die-at(i32 %t65, ptr %t66)
  br label %cond.end4
cond.end4:
  %t67 = load ptr, ptr @g-body-stream, align 8
  %t68 = getelementptr inbounds [36 x i8], ptr @.str.304, i64 0, i64 0
  %t69 = load ptr, ptr %test.addr.45, align 8
  %t70 = getelementptr inbounds %Val, ptr %t69, i32 0, i32 1
  %t71 = load ptr, ptr %t70, align 8
  %t72 = load ptr, ptr %then-lbl.addr.29, align 8
  %t73 = load ptr, ptr %next-lbl.addr.34, align 8
  %t74 = call i32 (ptr, ptr, ...) @fprintf(ptr %t67, ptr %t68, ptr %t71, ptr %t72, ptr %t73)
  %t75 = load ptr, ptr @g-body-stream, align 8
  %t76 = getelementptr inbounds [5 x i8], ptr @.str.305, i64 0, i64 0
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
  %t89 = getelementptr inbounds [17 x i8], ptr @.str.306, i64 0, i64 0
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
  %t97 = getelementptr inbounds [5 x i8], ptr @.str.307, i64 0, i64 0
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
  %t103 = getelementptr inbounds [5 x i8], ptr @.str.308, i64 0, i64 0
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
  %t8 = getelementptr inbounds [25 x i8], ptr @.str.309, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = call i32 @new-label-id()
  store i32 %t10, ptr %id.addr.9, align 4
  %t12 = getelementptr inbounds [13 x i8], ptr @.str.310, i64 0, i64 0
  %t13 = load i32, ptr %id.addr.9, align 4
  %t14 = call ptr @fmt-i32(ptr %t12, i32 %t13)
  store ptr %t14, ptr %cond-lbl.addr.11, align 8
  %t16 = getelementptr inbounds [13 x i8], ptr @.str.311, i64 0, i64 0
  %t17 = load i32, ptr %id.addr.9, align 4
  %t18 = call ptr @fmt-i32(ptr %t16, i32 %t17)
  store ptr %t18, ptr %body-lbl.addr.15, align 8
  %t20 = getelementptr inbounds [12 x i8], ptr @.str.312, i64 0, i64 0
  %t21 = load i32, ptr %id.addr.9, align 4
  %t22 = call ptr @fmt-i32(ptr %t20, i32 %t21)
  store ptr %t22, ptr %end-lbl.addr.19, align 8
  %t23 = load ptr, ptr @g-body-stream, align 8
  %t24 = getelementptr inbounds [17 x i8], ptr @.str.313, i64 0, i64 0
  %t25 = load ptr, ptr %cond-lbl.addr.11, align 8
  %t26 = call i32 (ptr, ptr, ...) @fprintf(ptr %t23, ptr %t24, ptr %t25)
  %t27 = load ptr, ptr @g-body-stream, align 8
  %t28 = getelementptr inbounds [5 x i8], ptr @.str.314, i64 0, i64 0
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
  %t46 = getelementptr inbounds [27 x i8], ptr @.str.315, i64 0, i64 0
  call void @die-at(i32 %t45, ptr %t46)
  br label %cond.end1
cond.end1:
  %t47 = load ptr, ptr @g-body-stream, align 8
  %t48 = getelementptr inbounds [36 x i8], ptr @.str.316, i64 0, i64 0
  %t49 = load ptr, ptr %cond.addr.31, align 8
  %t50 = getelementptr inbounds %Val, ptr %t49, i32 0, i32 1
  %t51 = load ptr, ptr %t50, align 8
  %t52 = load ptr, ptr %body-lbl.addr.15, align 8
  %t53 = load ptr, ptr %end-lbl.addr.19, align 8
  %t54 = call i32 (ptr, ptr, ...) @fprintf(ptr %t47, ptr %t48, ptr %t51, ptr %t52, ptr %t53)
  %t55 = load ptr, ptr @g-body-stream, align 8
  %t56 = getelementptr inbounds [5 x i8], ptr @.str.317, i64 0, i64 0
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
  %t74 = getelementptr inbounds [17 x i8], ptr @.str.318, i64 0, i64 0
  %t75 = load ptr, ptr %cond-lbl.addr.11, align 8
  %t76 = call i32 (ptr, ptr, ...) @fprintf(ptr %t73, ptr %t74, ptr %t75)
  br label %cond.end3
cond.end3:
  %t77 = load ptr, ptr @g-body-stream, align 8
  %t78 = getelementptr inbounds [5 x i8], ptr @.str.319, i64 0, i64 0
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
  %coerced.addr.49 = alloca ptr, align 8
  %cv.addr.68 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [20 x i8], ptr @.str.320, i64 0, i64 0
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
  %t19 = getelementptr inbounds [28 x i8], ptr @.str.321, i64 0, i64 0
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
  %t39 = getelementptr inbounds [27 x i8], ptr @.str.322, i64 0, i64 0
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
  %t50 = load ptr, ptr %v.addr.44, align 8
  %t51 = load ptr, ptr %sym.addr.25, align 8
  %t52 = getelementptr inbounds %Sym, ptr %t51, i32 0, i32 1
  %t53 = load ptr, ptr %t52, align 8
  %t54 = load ptr, ptr %cc.addr.0, align 8
  %t55 = getelementptr inbounds %Node, ptr %t54, i32 0, i32 1
  %t56 = load i32, ptr %t55, align 4
  %t57 = call ptr @coerce-int-val(ptr %t50, ptr %t53, i32 %t56)
  store ptr %t57, ptr %coerced.addr.49, align 8
  %t58 = load ptr, ptr %coerced.addr.49, align 8
  %t59 = icmp eq ptr %t58, null
  br i1 %t59, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t60 = load ptr, ptr %cc.addr.0, align 8
  %t61 = getelementptr inbounds %Node, ptr %t60, i32 0, i32 1
  %t62 = load i32, ptr %t61, align 4
  %t63 = getelementptr inbounds [29 x i8], ptr @.str.323, i64 0, i64 0
  %t64 = load ptr, ptr %target.addr.9, align 8
  %t65 = getelementptr inbounds %Node, ptr %t64, i32 0, i32 3
  %t66 = load ptr, ptr %t65, align 8
  %t67 = call ptr @fmt-s(ptr %t63, ptr %t66)
  call void @die-at(i32 %t62, ptr %t67)
  br label %cond.end4
cond.end4:
  %t69 = load ptr, ptr %coerced.addr.49, align 8
  store ptr %t69, ptr %cv.addr.68, align 8
  %t70 = load ptr, ptr @g-body-stream, align 8
  %t71 = getelementptr inbounds [33 x i8], ptr @.str.324, i64 0, i64 0
  %t72 = load ptr, ptr %sym.addr.25, align 8
  %t73 = getelementptr inbounds %Sym, ptr %t72, i32 0, i32 1
  %t74 = load ptr, ptr %t73, align 8
  %t75 = call ptr @type-to-ir(ptr %t74)
  %t76 = load ptr, ptr %cv.addr.68, align 8
  %t77 = getelementptr inbounds %Val, ptr %t76, i32 0, i32 1
  %t78 = load ptr, ptr %t77, align 8
  %t79 = load ptr, ptr %sym.addr.25, align 8
  %t80 = getelementptr inbounds %Sym, ptr %t79, i32 0, i32 2
  %t81 = load ptr, ptr %t80, align 8
  %t82 = load ptr, ptr %sym.addr.25, align 8
  %t83 = getelementptr inbounds %Sym, ptr %t82, i32 0, i32 1
  %t84 = load ptr, ptr %t83, align 8
  %t85 = call i32 @type-size(ptr %t84)
  %t86 = call i32 (ptr, ptr, ...) @fprintf(ptr %t70, ptr %t71, ptr %t75, ptr %t78, ptr %t81, i32 %t85)
  %t87 = load ptr, ptr @ty-void, align 8
  %t88 = call ptr @alloc-val(ptr %t87, ptr null)
  ret ptr %t88
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
  %t8 = getelementptr inbounds [19 x i8], ptr @.str.325, i64 0, i64 0
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
  %t19 = getelementptr inbounds [28 x i8], ptr @.str.326, i64 0, i64 0
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
  %t39 = getelementptr inbounds [27 x i8], ptr @.str.327, i64 0, i64 0
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
  %t52 = getelementptr inbounds [22 x i8], ptr @.str.328, i64 0, i64 0
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
  %t66 = getelementptr inbounds [34 x i8], ptr @.str.329, i64 0, i64 0
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
  %t77 = getelementptr inbounds [25 x i8], ptr @.str.330, i64 0, i64 0
  %t78 = load ptr, ptr %t2.addr.74, align 8
  %t79 = load ptr, ptr %ir.addr.53, align 8
  %t80 = load ptr, ptr %t1.addr.63, align 8
  %t81 = call i32 (ptr, ptr, ...) @fprintf(ptr %t76, ptr %t77, ptr %t78, ptr %t79, ptr %t80)
  %t82 = load ptr, ptr @g-body-stream, align 8
  %t83 = getelementptr inbounds [33 x i8], ptr @.str.331, i64 0, i64 0
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
  %t19 = getelementptr inbounds [23 x i8], ptr @.str.332, i64 0, i64 0
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
  %t34 = getelementptr inbounds [28 x i8], ptr @.str.333, i64 0, i64 0
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
  %t105 = getelementptr inbounds [35 x i8], ptr @.str.334, i64 0, i64 0
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
  %t115 = getelementptr inbounds [40 x i8], ptr @.str.335, i64 0, i64 0
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
  %t130 = getelementptr inbounds [31 x i8], ptr @.str.336, i64 0, i64 0
  %t131 = load ptr, ptr @g-source-path, align 8
  %t132 = load ptr, ptr %mdef.addr.0, align 8
  %t133 = getelementptr inbounds %MacroDef, ptr %t132, i32 0, i32 0
  %t134 = load ptr, ptr %t133, align 8
  %t135 = call i32 (ptr, ptr, ...) @fprintf(ptr %t129, ptr %t130, ptr %t131, ptr %t134)
  call void @exit(i32 1)
  br label %cond.end10
cond.end10:
  %t136 = load ptr, ptr %result.addr.121, align 8
  %t137 = call ptr @desugar(ptr %t136)
  %t138 = load ptr, ptr %scope.addr, align 8
  %t139 = call ptr @emit-node(ptr %t137, ptr %t138)
  ret ptr %t139
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
  %op.addr.271 = alloca ptr, align 8
  %sym.addr.280 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [11 x i8], ptr @.str.337, i64 0, i64 0
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
  %t19 = getelementptr inbounds [25 x i8], ptr @.str.338, i64 0, i64 0
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
  %t46 = getelementptr inbounds [7 x i8], ptr @.str.339, i64 0, i64 0
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
  %t56 = getelementptr inbounds [35 x i8], ptr @.str.340, i64 0, i64 0
  %t57 = load ptr, ptr %tmp.addr.53, align 8
  %t58 = call i32 (ptr, ptr, ...) @fprintf(ptr %t55, ptr %t56, ptr %t57)
  %t59 = load ptr, ptr @ty-ptr, align 8
  %t60 = load ptr, ptr %tmp.addr.53, align 8
  %t61 = call ptr @alloc-val(ptr %t59, ptr %t60)
  ret ptr %t61
cond.end4:
  %t62 = load ptr, ptr %h.addr.20, align 8
  %t63 = getelementptr inbounds [14 x i8], ptr @.str.341, i64 0, i64 0
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
  %t70 = getelementptr inbounds [16 x i8], ptr @.str.342, i64 0, i64 0
  %t71 = call i32 @strcmp(ptr %t69, ptr %t70)
  %t72 = icmp eq i32 %t71, 0
  br i1 %t72, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t73 = load ptr, ptr %n.addr, align 8
  %t74 = load ptr, ptr %scope.addr, align 8
  %t75 = call ptr @emit-funcall-ptr-i32(ptr %t73, ptr %t74)
  ret ptr %t75
cond.end7:
  %t76 = load ptr, ptr %h.addr.20, align 8
  %t77 = getelementptr inbounds [16 x i8], ptr @.str.343, i64 0, i64 0
  %t78 = call i32 @strcmp(ptr %t76, ptr %t77)
  %t79 = icmp eq i32 %t78, 0
  br i1 %t79, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t80 = load ptr, ptr %n.addr, align 8
  %t81 = load ptr, ptr %scope.addr, align 8
  %t82 = call ptr @emit-funcall-ptr-i64(ptr %t80, ptr %t81)
  ret ptr %t82
cond.end8:
  %t83 = load ptr, ptr %h.addr.20, align 8
  %t84 = getelementptr inbounds [16 x i8], ptr @.str.344, i64 0, i64 0
  %t85 = call i32 @strcmp(ptr %t83, ptr %t84)
  %t86 = icmp eq i32 %t85, 0
  br i1 %t86, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t87 = load ptr, ptr %n.addr, align 8
  %t88 = load ptr, ptr %scope.addr, align 8
  %t89 = call ptr @emit-funcall-ptr-ptr(ptr %t87, ptr %t88)
  ret ptr %t89
cond.end9:
  %t90 = load ptr, ptr %h.addr.20, align 8
  %t91 = getelementptr inbounds [7 x i8], ptr @.str.345, i64 0, i64 0
  %t92 = call i32 @strcmp(ptr %t90, ptr %t91)
  %t93 = icmp eq i32 %t92, 0
  br i1 %t93, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t94 = load ptr, ptr %n.addr, align 8
  %t95 = load ptr, ptr %scope.addr, align 8
  %t96 = call ptr @emit-return(ptr %t94, ptr %t95)
  ret ptr %t96
cond.end10:
  %t97 = load ptr, ptr %h.addr.20, align 8
  %t98 = getelementptr inbounds [3 x i8], ptr @.str.346, i64 0, i64 0
  %t99 = call i32 @strcmp(ptr %t97, ptr %t98)
  %t100 = icmp eq i32 %t99, 0
  br i1 %t100, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t101 = load ptr, ptr %n.addr, align 8
  %t102 = load ptr, ptr %scope.addr, align 8
  %t103 = call ptr @emit-do(ptr %t101, ptr %t102)
  ret ptr %t103
cond.end11:
  %t104 = load ptr, ptr %h.addr.20, align 8
  %t105 = getelementptr inbounds [4 x i8], ptr @.str.347, i64 0, i64 0
  %t106 = call i32 @strcmp(ptr %t104, ptr %t105)
  %t107 = icmp eq i32 %t106, 0
  br i1 %t107, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t108 = load ptr, ptr %n.addr, align 8
  %t109 = load ptr, ptr %scope.addr, align 8
  %t110 = call ptr @emit-let(ptr %t108, ptr %t109)
  ret ptr %t110
cond.end12:
  %t111 = load ptr, ptr %h.addr.20, align 8
  %t112 = getelementptr inbounds [5 x i8], ptr @.str.348, i64 0, i64 0
  %t113 = call i32 @strcmp(ptr %t111, ptr %t112)
  %t114 = icmp eq i32 %t113, 0
  br i1 %t114, label %cond.then13.0, label %cond.end13
cond.then13.0:
  %t115 = load ptr, ptr %n.addr, align 8
  %t116 = load ptr, ptr %scope.addr, align 8
  %t117 = call ptr @emit-cond(ptr %t115, ptr %t116)
  ret ptr %t117
cond.end13:
  %t118 = load ptr, ptr %h.addr.20, align 8
  %t119 = getelementptr inbounds [6 x i8], ptr @.str.349, i64 0, i64 0
  %t120 = call i32 @strcmp(ptr %t118, ptr %t119)
  %t121 = icmp eq i32 %t120, 0
  br i1 %t121, label %cond.then14.0, label %cond.end14
cond.then14.0:
  %t122 = load ptr, ptr %n.addr, align 8
  %t123 = call ptr @emit-quote(ptr %t122)
  ret ptr %t123
cond.end14:
  %t124 = load ptr, ptr %h.addr.20, align 8
  %t125 = getelementptr inbounds [11 x i8], ptr @.str.350, i64 0, i64 0
  %t126 = call i32 @strcmp(ptr %t124, ptr %t125)
  %t127 = icmp eq i32 %t126, 0
  br i1 %t127, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t128 = load ptr, ptr %n.addr, align 8
  %t129 = load ptr, ptr %scope.addr, align 8
  %t130 = call ptr @emit-quasiquote(ptr %t128, ptr %t129)
  ret ptr %t130
cond.end15:
  %t131 = load ptr, ptr %h.addr.20, align 8
  %t132 = getelementptr inbounds [6 x i8], ptr @.str.351, i64 0, i64 0
  %t133 = call i32 @strcmp(ptr %t131, ptr %t132)
  %t134 = icmp eq i32 %t133, 0
  br i1 %t134, label %cond.then16.0, label %cond.end16
cond.then16.0:
  %t135 = load ptr, ptr %n.addr, align 8
  %t136 = load ptr, ptr %scope.addr, align 8
  %t137 = call ptr @emit-while(ptr %t135, ptr %t136)
  ret ptr %t137
cond.end16:
  %t138 = load ptr, ptr %h.addr.20, align 8
  %t139 = getelementptr inbounds [5 x i8], ptr @.str.352, i64 0, i64 0
  %t140 = call i32 @strcmp(ptr %t138, ptr %t139)
  %t141 = icmp eq i32 %t140, 0
  br i1 %t141, label %cond.then17.0, label %cond.end17
cond.then17.0:
  %t142 = load ptr, ptr %n.addr, align 8
  %t143 = load ptr, ptr %scope.addr, align 8
  %t144 = call ptr @emit-set(ptr %t142, ptr %t143)
  ret ptr %t144
cond.end17:
  %t145 = load ptr, ptr %h.addr.20, align 8
  %t146 = getelementptr inbounds [5 x i8], ptr @.str.353, i64 0, i64 0
  %t147 = call i32 @strcmp(ptr %t145, ptr %t146)
  %t148 = icmp eq i32 %t147, 0
  br i1 %t148, label %cond.then18.0, label %cond.end18
cond.then18.0:
  %t149 = load ptr, ptr %n.addr, align 8
  %t150 = load ptr, ptr %scope.addr, align 8
  %t151 = call ptr @emit-inc(ptr %t149, ptr %t150)
  ret ptr %t151
cond.end18:
  %t152 = load ptr, ptr %h.addr.20, align 8
  %t153 = getelementptr inbounds [4 x i8], ptr @.str.354, i64 0, i64 0
  %t154 = call i32 @strcmp(ptr %t152, ptr %t153)
  %t155 = icmp eq i32 %t154, 0
  br i1 %t155, label %cond.then19.0, label %cond.end19
cond.then19.0:
  %t156 = load ptr, ptr %n.addr, align 8
  %t157 = load ptr, ptr %scope.addr, align 8
  %t158 = call ptr @emit-not(ptr %t156, ptr %t157)
  ret ptr %t158
cond.end19:
  %t159 = load ptr, ptr %h.addr.20, align 8
  %t160 = getelementptr inbounds [4 x i8], ptr @.str.355, i64 0, i64 0
  %t161 = call i32 @strcmp(ptr %t159, ptr %t160)
  %t162 = icmp eq i32 %t161, 0
  br i1 %t162, label %cond.then20.0, label %cond.end20
cond.then20.0:
  %t163 = load ptr, ptr %n.addr, align 8
  %t164 = load ptr, ptr %scope.addr, align 8
  %t165 = call ptr @emit-short-circuit(ptr %t163, ptr %t164, i32 1)
  ret ptr %t165
cond.end20:
  %t166 = load ptr, ptr %h.addr.20, align 8
  %t167 = getelementptr inbounds [3 x i8], ptr @.str.356, i64 0, i64 0
  %t168 = call i32 @strcmp(ptr %t166, ptr %t167)
  %t169 = icmp eq i32 %t168, 0
  br i1 %t169, label %cond.then21.0, label %cond.end21
cond.then21.0:
  %t170 = load ptr, ptr %n.addr, align 8
  %t171 = load ptr, ptr %scope.addr, align 8
  %t172 = call ptr @emit-short-circuit(ptr %t170, ptr %t171, i32 0)
  ret ptr %t172
cond.end21:
  %t173 = load ptr, ptr %h.addr.20, align 8
  %t174 = getelementptr inbounds [5 x i8], ptr @.str.357, i64 0, i64 0
  %t175 = call i32 @strcmp(ptr %t173, ptr %t174)
  %t176 = icmp eq i32 %t175, 0
  br i1 %t176, label %cond.then22.0, label %cond.end22
cond.then22.0:
  %t177 = load ptr, ptr %n.addr, align 8
  %t178 = load ptr, ptr %scope.addr, align 8
  %t179 = call ptr @emit-cast(ptr %t177, ptr %t178)
  ret ptr %t179
cond.end22:
  %t180 = load ptr, ptr %h.addr.20, align 8
  %t181 = getelementptr inbounds [8 x i8], ptr @.str.358, i64 0, i64 0
  %t182 = call i32 @strcmp(ptr %t180, ptr %t181)
  %t183 = icmp eq i32 %t182, 0
  br i1 %t183, label %cond.then23.0, label %cond.end23
cond.then23.0:
  %t184 = load ptr, ptr %n.addr, align 8
  %t185 = load ptr, ptr %scope.addr, align 8
  %t186 = call ptr @emit-addr-of(ptr %t184, ptr %t185)
  ret ptr %t186
cond.end23:
  %t187 = load ptr, ptr %h.addr.20, align 8
  %t188 = getelementptr inbounds [13 x i8], ptr @.str.359, i64 0, i64 0
  %t189 = call i32 @strcmp(ptr %t187, ptr %t188)
  %t190 = icmp eq i32 %t189, 0
  br i1 %t190, label %cond.then24.0, label %cond.end24
cond.then24.0:
  %t191 = load ptr, ptr %n.addr, align 8
  %t192 = load ptr, ptr %scope.addr, align 8
  %t193 = call ptr @emit-funcall-void(ptr %t191, ptr %t192)
  ret ptr %t193
cond.end24:
  %t194 = load ptr, ptr %h.addr.20, align 8
  %t195 = getelementptr inbounds [8 x i8], ptr @.str.360, i64 0, i64 0
  %t196 = call i32 @strcmp(ptr %t194, ptr %t195)
  %t197 = icmp eq i32 %t196, 0
  br i1 %t197, label %cond.then25.0, label %cond.end25
cond.then25.0:
  %t198 = load ptr, ptr %n.addr, align 8
  %t199 = load ptr, ptr %scope.addr, align 8
  %t200 = call ptr @emit-funcall(ptr %t198, ptr %t199)
  ret ptr %t200
cond.end25:
  %t201 = load ptr, ptr %h.addr.20, align 8
  %t202 = getelementptr inbounds [6 x i8], ptr @.str.361, i64 0, i64 0
  %t203 = call i32 @strcmp(ptr %t201, ptr %t202)
  %t204 = icmp eq i32 %t203, 0
  br i1 %t204, label %cond.then26.0, label %cond.end26
cond.then26.0:
  %t205 = load ptr, ptr %n.addr, align 8
  %t206 = load ptr, ptr %scope.addr, align 8
  %t207 = call ptr @emit-deref(ptr %t205, ptr %t206)
  ret ptr %t207
cond.end26:
  %t208 = load ptr, ptr %h.addr.20, align 8
  %t209 = getelementptr inbounds [9 x i8], ptr @.str.362, i64 0, i64 0
  %t210 = call i32 @strcmp(ptr %t208, ptr %t209)
  %t211 = icmp eq i32 %t210, 0
  br i1 %t211, label %cond.then27.0, label %cond.end27
cond.then27.0:
  %t212 = load ptr, ptr %n.addr, align 8
  %t213 = load ptr, ptr %scope.addr, align 8
  %t214 = call ptr @emit-ptr-set(ptr %t212, ptr %t213)
  ret ptr %t214
cond.end27:
  %t215 = load ptr, ptr %h.addr.20, align 8
  %t216 = getelementptr inbounds [5 x i8], ptr @.str.363, i64 0, i64 0
  %t217 = call i32 @strcmp(ptr %t215, ptr %t216)
  %t218 = icmp eq i32 %t217, 0
  br i1 %t218, label %cond.then28.0, label %cond.end28
cond.then28.0:
  %t219 = load ptr, ptr %n.addr, align 8
  %t220 = load ptr, ptr %scope.addr, align 8
  %t221 = call ptr @emit-ptr-add(ptr %t219, ptr %t220)
  ret ptr %t221
cond.end28:
  %t222 = load ptr, ptr %h.addr.20, align 8
  %t223 = getelementptr inbounds [2 x i8], ptr @.str.364, i64 0, i64 0
  %t224 = call i32 @strcmp(ptr %t222, ptr %t223)
  %t225 = icmp eq i32 %t224, 0
  br i1 %t225, label %cond.then29.0, label %cond.end29
cond.then29.0:
  %t226 = load ptr, ptr %n.addr, align 8
  %t227 = load ptr, ptr %scope.addr, align 8
  %t228 = call ptr @emit-field-get(ptr %t226, ptr %t227)
  ret ptr %t228
cond.end29:
  %t229 = load ptr, ptr %h.addr.20, align 8
  %t230 = getelementptr inbounds [6 x i8], ptr @.str.365, i64 0, i64 0
  %t231 = call i32 @strcmp(ptr %t229, ptr %t230)
  %t232 = icmp eq i32 %t231, 0
  br i1 %t232, label %cond.then30.0, label %cond.end30
cond.then30.0:
  %t233 = load ptr, ptr %n.addr, align 8
  %t234 = load ptr, ptr %scope.addr, align 8
  %t235 = call ptr @emit-field-set(ptr %t233, ptr %t234)
  ret ptr %t235
cond.end30:
  %t236 = load ptr, ptr %h.addr.20, align 8
  %t237 = getelementptr inbounds [7 x i8], ptr @.str.366, i64 0, i64 0
  %t238 = call i32 @strcmp(ptr %t236, ptr %t237)
  %t239 = icmp eq i32 %t238, 0
  br i1 %t239, label %cond.then31.0, label %cond.end31
cond.then31.0:
  %t240 = load ptr, ptr %n.addr, align 8
  %t241 = load ptr, ptr %scope.addr, align 8
  %t242 = call ptr @emit-sizeof(ptr %t240, ptr %t241)
  ret ptr %t242
cond.end31:
  %t243 = load ptr, ptr %h.addr.20, align 8
  %t244 = getelementptr inbounds [7 x i8], ptr @.str.367, i64 0, i64 0
  %t245 = call i32 @strcmp(ptr %t243, ptr %t244)
  %t246 = icmp eq i32 %t245, 0
  br i1 %t246, label %cond.then32.0, label %cond.end32
cond.then32.0:
  %t247 = load ptr, ptr %n.addr, align 8
  %t248 = load ptr, ptr %scope.addr, align 8
  %t249 = call ptr @emit-alloca-form(ptr %t247, ptr %t248)
  ret ptr %t249
cond.end32:
  %t250 = load ptr, ptr %h.addr.20, align 8
  %t251 = getelementptr inbounds [5 x i8], ptr @.str.368, i64 0, i64 0
  %t252 = call i32 @strcmp(ptr %t250, ptr %t251)
  %t253 = icmp eq i32 %t252, 0
  br i1 %t253, label %cond.then33.0, label %cond.end33
cond.then33.0:
  %t254 = load ptr, ptr %n.addr, align 8
  %t255 = load ptr, ptr %scope.addr, align 8
  %t256 = call ptr @emit-char(ptr %t254, ptr %t255)
  ret ptr %t256
cond.end33:
  %t257 = load ptr, ptr %h.addr.20, align 8
  %t258 = getelementptr inbounds [5 x i8], ptr @.str.369, i64 0, i64 0
  %t259 = call i32 @strcmp(ptr %t257, ptr %t258)
  %t260 = icmp eq i32 %t259, 0
  br i1 %t260, label %cond.then34.0, label %cond.end34
cond.then34.0:
  %t261 = load ptr, ptr %n.addr, align 8
  %t262 = load ptr, ptr %scope.addr, align 8
  %t263 = call ptr @emit-aref(ptr %t261, ptr %t262)
  ret ptr %t263
cond.end34:
  %t264 = load ptr, ptr %h.addr.20, align 8
  %t265 = getelementptr inbounds [6 x i8], ptr @.str.370, i64 0, i64 0
  %t266 = call i32 @strcmp(ptr %t264, ptr %t265)
  %t267 = icmp eq i32 %t266, 0
  br i1 %t267, label %cond.then35.0, label %cond.end35
cond.then35.0:
  %t268 = load ptr, ptr %n.addr, align 8
  %t269 = load ptr, ptr %scope.addr, align 8
  %t270 = call ptr @emit-aset(ptr %t268, ptr %t269)
  ret ptr %t270
cond.end35:
  %t272 = load ptr, ptr %h.addr.20, align 8
  %t273 = call ptr @lookup-binop(ptr %t272)
  store ptr %t273, ptr %op.addr.271, align 8
  %t274 = load ptr, ptr %op.addr.271, align 8
  %t275 = icmp ne ptr %t274, null
  br i1 %t275, label %cond.then36.0, label %cond.end36
cond.then36.0:
  %t276 = load ptr, ptr %n.addr, align 8
  %t277 = load ptr, ptr %scope.addr, align 8
  %t278 = load ptr, ptr %op.addr.271, align 8
  %t279 = call ptr @emit-binop(ptr %t276, ptr %t277, ptr %t278)
  ret ptr %t279
cond.end36:
  %t281 = load ptr, ptr %scope.addr, align 8
  %t282 = load ptr, ptr %h.addr.20, align 8
  %t283 = call ptr @scope-lookup(ptr %t281, ptr %t282)
  store ptr %t283, ptr %sym.addr.280, align 8
  %t284 = load ptr, ptr %sym.addr.280, align 8
  %t285 = icmp eq ptr %t284, null
  br i1 %t285, label %cond.then37.0, label %cond.end37
cond.then37.0:
  %t286 = load ptr, ptr %head.addr.9, align 8
  %t287 = getelementptr inbounds %Node, ptr %t286, i32 0, i32 1
  %t288 = load i32, ptr %t287, align 4
  %t289 = getelementptr inbounds [12 x i8], ptr @.str.371, i64 0, i64 0
  %t290 = load ptr, ptr %h.addr.20, align 8
  %t291 = call ptr @fmt-s(ptr %t289, ptr %t290)
  call void @die-at(i32 %t288, ptr %t291)
  br label %cond.end37
cond.end37:
  %t292 = load ptr, ptr %n.addr, align 8
  %t293 = load ptr, ptr %scope.addr, align 8
  %t294 = load ptr, ptr %sym.addr.280, align 8
  %t295 = call ptr @emit-call(ptr %t292, ptr %t293, ptr %t294)
  ret ptr %t295
}

define void @emit-defvar(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %or.val1 = alloca i1, align 1
  %name-node.addr.13 = alloca ptr, align 8
  %name.addr.16 = alloca ptr, align 8
  %type-name.addr.17 = alloca ptr, align 8
  %ty.addr.27 = alloca ptr, align 8
  %ir-name.addr.33 = alloca ptr, align 8
  %align.addr.37 = alloca i32, align 4
  %init.addr.43 = alloca ptr, align 8
  %zero.addr.64 = alloca ptr, align 8
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
  %t12 = getelementptr inbounds [39 x i8], ptr @.str.372, i64 0, i64 0
  call void @die-at(i32 %t11, ptr %t12)
  br label %cond.end0
cond.end0:
  %t14 = load ptr, ptr %cc.addr.0, align 8
  %t15 = call ptr @node-at(ptr %t14, i32 1)
  store ptr %t15, ptr %name-node.addr.13, align 8
  store ptr null, ptr %name.addr.16, align 8
  store ptr null, ptr %type-name.addr.17, align 8
  %t18 = load ptr, ptr %name-node.addr.13, align 8
  call void @extract-name-type(ptr %t18, ptr %name.addr.16, ptr %type-name.addr.17)
  %t19 = load ptr, ptr %type-name.addr.17, align 8
  %t20 = icmp eq ptr %t19, null
  br i1 %t20, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t21 = load ptr, ptr %name-node.addr.13, align 8
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 1
  %t23 = load i32, ptr %t22, align 4
  %t24 = getelementptr inbounds [30 x i8], ptr @.str.373, i64 0, i64 0
  %t25 = load ptr, ptr %name.addr.16, align 8
  %t26 = call ptr @fmt-s(ptr %t24, ptr %t25)
  call void @die-at(i32 %t23, ptr %t26)
  br label %cond.end2
cond.end2:
  %t28 = load ptr, ptr %type-name.addr.17, align 8
  %t29 = load ptr, ptr %name-node.addr.13, align 8
  %t30 = getelementptr inbounds %Node, ptr %t29, i32 0, i32 1
  %t31 = load i32, ptr %t30, align 4
  %t32 = call ptr @parse-type-name(ptr %t28, i32 %t31)
  store ptr %t32, ptr %ty.addr.27, align 8
  %t34 = getelementptr inbounds [4 x i8], ptr @.str.374, i64 0, i64 0
  %t35 = load ptr, ptr %name.addr.16, align 8
  %t36 = call ptr @fmt-s(ptr %t34, ptr %t35)
  store ptr %t36, ptr %ir-name.addr.33, align 8
  %t38 = load ptr, ptr %ty.addr.27, align 8
  %t39 = call i32 @type-size(ptr %t38)
  store i32 %t39, ptr %align.addr.37, align 4
  %t40 = load ptr, ptr %cc.addr.0, align 8
  %t41 = call i32 @node-len(ptr %t40)
  %t42 = icmp eq i32 %t41, 3
  br i1 %t42, label %cond.then3.0, label %cond.test3.1
cond.then3.0:
  %t44 = load ptr, ptr %cc.addr.0, align 8
  %t45 = call ptr @node-at(ptr %t44, i32 2)
  store ptr %t45, ptr %init.addr.43, align 8
  %t46 = load ptr, ptr %init.addr.43, align 8
  %t47 = getelementptr inbounds %Node, ptr %t46, i32 0, i32 0
  %t48 = load i32, ptr %t47, align 4
  %t49 = icmp ne i32 %t48, 0
  br i1 %t49, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t50 = load ptr, ptr %init.addr.43, align 8
  %t51 = getelementptr inbounds %Node, ptr %t50, i32 0, i32 1
  %t52 = load i32, ptr %t51, align 4
  %t53 = getelementptr inbounds [37 x i8], ptr @.str.375, i64 0, i64 0
  call void @die-at(i32 %t52, ptr %t53)
  br label %cond.end4
cond.end4:
  %t54 = load ptr, ptr @g-out, align 8
  %t55 = getelementptr inbounds [31 x i8], ptr @.str.376, i64 0, i64 0
  %t56 = load ptr, ptr %ir-name.addr.33, align 8
  %t57 = load ptr, ptr %ty.addr.27, align 8
  %t58 = call ptr @type-to-ir(ptr %t57)
  %t59 = load ptr, ptr %init.addr.43, align 8
  %t60 = getelementptr inbounds %Node, ptr %t59, i32 0, i32 2
  %t61 = load i64, ptr %t60, align 8
  %t62 = load i32, ptr %align.addr.37, align 4
  %t63 = call i32 (ptr, ptr, ...) @fprintf(ptr %t54, ptr %t55, ptr %t56, ptr %t58, i64 %t61, i32 %t62)
  br label %cond.end3
cond.test3.1:
  br i1 1, label %cond.then3.1, label %cond.end3
cond.then3.1:
  %t65 = getelementptr inbounds [2 x i8], ptr @.str.377, i64 0, i64 0
  store ptr %t65, ptr %zero.addr.64, align 8
  %t66 = load ptr, ptr %ty.addr.27, align 8
  %t67 = getelementptr inbounds %Type, ptr %t66, i32 0, i32 0
  %t68 = load i32, ptr %t67, align 4
  %t69 = icmp eq i32 %t68, 10
  br i1 %t69, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t70 = getelementptr inbounds [5 x i8], ptr @.str.378, i64 0, i64 0
  store ptr %t70, ptr %zero.addr.64, align 8
  br label %cond.end5
cond.end5:
  %t71 = load ptr, ptr @g-out, align 8
  %t72 = getelementptr inbounds [30 x i8], ptr @.str.379, i64 0, i64 0
  %t73 = load ptr, ptr %ir-name.addr.33, align 8
  %t74 = load ptr, ptr %ty.addr.27, align 8
  %t75 = call ptr @type-to-ir(ptr %t74)
  %t76 = load ptr, ptr %zero.addr.64, align 8
  %t77 = load i32, ptr %align.addr.37, align 4
  %t78 = call i32 (ptr, ptr, ...) @fprintf(ptr %t71, ptr %t72, ptr %t73, ptr %t75, ptr %t76, i32 %t77)
  br label %cond.end3
cond.end3:
  %t79 = load ptr, ptr @g-globals, align 8
  %t80 = load ptr, ptr %name.addr.16, align 8
  %t81 = load ptr, ptr %ty.addr.27, align 8
  %t82 = load ptr, ptr %ir-name.addr.33, align 8
  %t83 = call ptr @scope-define(ptr %t79, ptr %t80, ptr %t81, ptr %t82, i32 1)
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
  %t8 = getelementptr inbounds [33 x i8], ptr @.str.380, i64 0, i64 0
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
  %t22 = getelementptr inbounds [30 x i8], ptr @.str.381, i64 0, i64 0
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
  %t30 = getelementptr inbounds [40 x i8], ptr @.str.382, i64 0, i64 0
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
  %t41 = getelementptr inbounds [4 x i8], ptr @.str.383, i64 0, i64 0
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
  %t8 = getelementptr inbounds [22 x i8], ptr @.str.384, i64 0, i64 0
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
  %t25 = getelementptr inbounds [30 x i8], ptr @.str.385, i64 0, i64 0
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
  %t36 = getelementptr inbounds [3 x i8], ptr @.str.386, i64 0, i64 0
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
  %fname.addr.55 = alloca ptr, align 8
  %fty.addr.56 = alloca ptr, align 8
  %i.addr.92 = alloca i32, align 4
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
  %t8 = getelementptr inbounds [24 x i8], ptr @.str.387, i64 0, i64 0
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
  %t19 = getelementptr inbounds [31 x i8], ptr @.str.388, i64 0, i64 0
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
  store ptr null, ptr %fname.addr.55, align 8
  %t57 = load ptr, ptr %field.addr.50, align 8
  %t58 = load ptr, ptr %field.addr.50, align 8
  %t59 = getelementptr inbounds %Node, ptr %t58, i32 0, i32 1
  %t60 = load i32, ptr %t59, align 4
  %t61 = call ptr @extract-name-and-type(ptr %t57, ptr %fname.addr.55, i32 %t60)
  store ptr %t61, ptr %fty.addr.56, align 8
  %t62 = load ptr, ptr %fty.addr.56, align 8
  %t63 = icmp eq ptr %t62, null
  br i1 %t63, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t64 = load ptr, ptr %field.addr.50, align 8
  %t65 = getelementptr inbounds %Node, ptr %t64, i32 0, i32 1
  %t66 = load i32, ptr %t65, align 4
  %t67 = getelementptr inbounds [36 x i8], ptr @.str.389, i64 0, i64 0
  %t68 = load ptr, ptr %fname.addr.55, align 8
  %t69 = call ptr @fmt-s(ptr %t67, ptr %t68)
  call void @die-at(i32 %t66, ptr %t69)
  br label %cond.end3
cond.end3:
  %t70 = load ptr, ptr %sd.addr.20, align 8
  %t71 = getelementptr inbounds %StructDef, ptr %t70, i32 0, i32 1
  %t72 = load ptr, ptr %t71, align 8
  %t73 = load i32, ptr %i.addr.46, align 4
  %t74 = sext i32 %t73 to i64
  %t75 = load ptr, ptr %fname.addr.55, align 8
  %t76 = getelementptr inbounds ptr, ptr %t72, i64 %t74
  store ptr %t75, ptr %t76, align 8
  %t77 = load ptr, ptr %sd.addr.20, align 8
  %t78 = getelementptr inbounds %StructDef, ptr %t77, i32 0, i32 2
  %t79 = load ptr, ptr %t78, align 8
  %t80 = load i32, ptr %i.addr.46, align 4
  %t81 = sext i32 %t80 to i64
  %t82 = load ptr, ptr %fty.addr.56, align 8
  %t83 = getelementptr inbounds ptr, ptr %t79, i64 %t81
  store ptr %t82, ptr %t83, align 8
  %t84 = load i32, ptr %i.addr.46, align 4
  %t85 = add nsw i32 %t84, 1
  store i32 %t85, ptr %i.addr.46, align 4
  br label %while.cond2
while.end2:
  %t86 = load ptr, ptr @g-out, align 8
  %t87 = getelementptr inbounds [15 x i8], ptr @.str.390, i64 0, i64 0
  %t88 = load ptr, ptr %name-node.addr.9, align 8
  %t89 = getelementptr inbounds %Node, ptr %t88, i32 0, i32 3
  %t90 = load ptr, ptr %t89, align 8
  %t91 = call i32 (ptr, ptr, ...) @fprintf(ptr %t86, ptr %t87, ptr %t90)
  store i32 0, ptr %i.addr.92, align 4
  br label %while.cond4
while.cond4:
  %t93 = load i32, ptr %i.addr.92, align 4
  %t94 = load i32, ptr %nfields.addr.25, align 4
  %t95 = icmp slt i32 %t93, %t94
  br i1 %t95, label %while.body4, label %while.end4
while.body4:
  %t96 = load i32, ptr %i.addr.92, align 4
  %t97 = icmp ne i32 %t96, 0
  br i1 %t97, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t98 = load ptr, ptr @g-out, align 8
  %t99 = getelementptr inbounds [3 x i8], ptr @.str.391, i64 0, i64 0
  %t100 = call i32 (ptr, ptr, ...) @fprintf(ptr %t98, ptr %t99)
  br label %cond.end5
cond.end5:
  %t101 = load ptr, ptr @g-out, align 8
  %t102 = getelementptr inbounds [3 x i8], ptr @.str.392, i64 0, i64 0
  %t103 = load ptr, ptr %sd.addr.20, align 8
  %t104 = getelementptr inbounds %StructDef, ptr %t103, i32 0, i32 2
  %t105 = load ptr, ptr %t104, align 8
  %t106 = load i32, ptr %i.addr.92, align 4
  %t107 = sext i32 %t106 to i64
  %t108 = getelementptr inbounds ptr, ptr %t105, i64 %t107
  %t109 = load ptr, ptr %t108, align 8
  %t110 = call ptr @type-to-ir(ptr %t109)
  %t111 = call i32 (ptr, ptr, ...) @fprintf(ptr %t101, ptr %t102, ptr %t110)
  %t112 = load i32, ptr %i.addr.92, align 4
  %t113 = add nsw i32 %t112, 1
  store i32 %t113, ptr %i.addr.92, align 4
  br label %while.cond4
while.end4:
  %t114 = load ptr, ptr @g-out, align 8
  %t115 = getelementptr inbounds [5 x i8], ptr @.str.393, i64 0, i64 0
  %t116 = call i32 (ptr, ptr, ...) @fprintf(ptr %t114, ptr %t115)
  ret void
}

define void @emit-extern(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %arg1.addr.9 = alloca ptr, align 8
  %name.addr.12 = alloca ptr, align 8
  %type-name.addr.13 = alloca ptr, align 8
  %ty.addr.23 = alloca ptr, align 8
  %ir-name.addr.29 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [26 x i8], ptr @.str.394, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %arg1.addr.9, align 8
  store ptr null, ptr %name.addr.12, align 8
  store ptr null, ptr %type-name.addr.13, align 8
  %t14 = load ptr, ptr %arg1.addr.9, align 8
  call void @extract-name-type(ptr %t14, ptr %name.addr.12, ptr %type-name.addr.13)
  %t15 = load ptr, ptr %type-name.addr.13, align 8
  %t16 = icmp eq ptr %t15, null
  br i1 %t16, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t17 = load ptr, ptr %arg1.addr.9, align 8
  %t18 = getelementptr inbounds %Node, ptr %t17, i32 0, i32 1
  %t19 = load i32, ptr %t18, align 4
  %t20 = getelementptr inbounds [30 x i8], ptr @.str.395, i64 0, i64 0
  %t21 = load ptr, ptr %name.addr.12, align 8
  %t22 = call ptr @fmt-s(ptr %t20, ptr %t21)
  call void @die-at(i32 %t19, ptr %t22)
  br label %cond.end1
cond.end1:
  %t24 = load ptr, ptr %type-name.addr.13, align 8
  %t25 = load ptr, ptr %arg1.addr.9, align 8
  %t26 = getelementptr inbounds %Node, ptr %t25, i32 0, i32 1
  %t27 = load i32, ptr %t26, align 4
  %t28 = call ptr @parse-type-name(ptr %t24, i32 %t27)
  store ptr %t28, ptr %ty.addr.23, align 8
  %t30 = getelementptr inbounds [4 x i8], ptr @.str.396, i64 0, i64 0
  %t31 = load ptr, ptr %name.addr.12, align 8
  %t32 = call ptr @fmt-s(ptr %t30, ptr %t31)
  store ptr %t32, ptr %ir-name.addr.29, align 8
  %t33 = load ptr, ptr @g-out, align 8
  %t34 = getelementptr inbounds [26 x i8], ptr @.str.397, i64 0, i64 0
  %t35 = load ptr, ptr %ir-name.addr.29, align 8
  %t36 = load ptr, ptr %ty.addr.23, align 8
  %t37 = call ptr @type-to-ir(ptr %t36)
  %t38 = call i32 (ptr, ptr, ...) @fprintf(ptr %t33, ptr %t34, ptr %t35, ptr %t37)
  %t39 = load ptr, ptr @g-globals, align 8
  %t40 = load ptr, ptr %name.addr.12, align 8
  %t41 = load ptr, ptr %ty.addr.23, align 8
  %t42 = load ptr, ptr %ir-name.addr.29, align 8
  %t43 = call ptr @scope-define(ptr %t39, ptr %t40, ptr %t41, ptr %t42, i32 1)
  ret void
}

define void @emit-include(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %or.val1 = alloca i1, align 1
  %mod.addr.15 = alloca ptr, align 8
  %header.addr.20 = alloca ptr, align 8
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
  %t14 = getelementptr inbounds [28 x i8], ptr @.str.398, i64 0, i64 0
  call void @die-at(i32 %t13, ptr %t14)
  br label %cond.end0
cond.end0:
  %t16 = load ptr, ptr %cc.addr.0, align 8
  %t17 = call ptr @node-at(ptr %t16, i32 1)
  %t18 = getelementptr inbounds %Node, ptr %t17, i32 0, i32 3
  %t19 = load ptr, ptr %t18, align 8
  store ptr %t19, ptr %mod.addr.15, align 8
  %t21 = getelementptr inbounds [5 x i8], ptr @.str.399, i64 0, i64 0
  %t22 = load ptr, ptr %mod.addr.15, align 8
  %t23 = call ptr @fmt-s(ptr %t21, ptr %t22)
  store ptr %t23, ptr %header.addr.20, align 8
  %t24 = load ptr, ptr %header.addr.20, align 8
  %t25 = load ptr, ptr %cc.addr.0, align 8
  %t26 = getelementptr inbounds %Node, ptr %t25, i32 0, i32 1
  %t27 = load i32, ptr %t26, align 4
  call void @emit-c-include(ptr %t24, i32 %t27)
  ret void
}

define i64 @c-skip-ws(ptr %buf.arg, i64 %pos.arg, i64 %len.arg) {
entry:
  %buf.addr = alloca ptr, align 8
  store ptr %buf.arg, ptr %buf.addr, align 8
  %pos.addr = alloca i64, align 8
  store i64 %pos.arg, ptr %pos.addr, align 8
  %len.addr = alloca i64, align 8
  store i64 %len.arg, ptr %len.addr, align 8
  %and.val1 = alloca i1, align 1
  br label %while.cond0
while.cond0:
  %t0 = load i64, ptr %pos.addr, align 8
  %t1 = load i64, ptr %len.addr, align 8
  %t2 = icmp slt i64 %t0, %t1
  store i1 %t2, ptr %and.val1, align 1
  br i1 %t2, label %and.rhs1, label %and.end1
and.rhs1:
  %t3 = load ptr, ptr %buf.addr, align 8
  %t4 = load i64, ptr %pos.addr, align 8
  %t5 = call i32 @char-at(ptr %t3, i64 %t4)
  %t6 = call i32 @isspace(i32 %t5)
  %t7 = icmp ne i32 %t6, 0
  store i1 %t7, ptr %and.val1, align 1
  br label %and.end1
and.end1:
  %t8 = load i1, ptr %and.val1, align 1
  br i1 %t8, label %while.body0, label %while.end0
while.body0:
  %t9 = load i64, ptr %pos.addr, align 8
  %t10 = sext i32 1 to i64
  %t11 = add nsw i64 %t9, %t10
  store i64 %t11, ptr %pos.addr, align 8
  br label %while.cond0
while.end0:
  %t12 = load i64, ptr %pos.addr, align 8
  ret i64 %t12
}

define ptr @c-read-ident(ptr %buf.arg, i64 %pos.arg, i64 %len.arg, ptr %out-end.arg) {
entry:
  %buf.addr = alloca ptr, align 8
  store ptr %buf.arg, ptr %buf.addr, align 8
  %pos.addr = alloca i64, align 8
  store i64 %pos.arg, ptr %pos.addr, align 8
  %len.addr = alloca i64, align 8
  store i64 %len.arg, ptr %len.addr, align 8
  %out-end.addr = alloca ptr, align 8
  store ptr %out-end.arg, ptr %out-end.addr, align 8
  %start.addr.0 = alloca i64, align 8
  %and.val1 = alloca i1, align 1
  %or.val2 = alloca i1, align 1
  %or.val3 = alloca i1, align 1
  %and.val4 = alloca i1, align 1
  %or.val5 = alloca i1, align 1
  %and.val6 = alloca i1, align 1
  %t1 = load i64, ptr %pos.addr, align 8
  store i64 %t1, ptr %start.addr.0, align 8
  br label %while.cond0
while.cond0:
  %t2 = load i64, ptr %pos.addr, align 8
  %t3 = load i64, ptr %len.addr, align 8
  %t4 = icmp slt i64 %t2, %t3
  store i1 %t4, ptr %and.val1, align 1
  br i1 %t4, label %and.rhs1, label %and.end1
and.rhs1:
  %t5 = load ptr, ptr %buf.addr, align 8
  %t6 = load i64, ptr %pos.addr, align 8
  %t7 = call i32 @char-at(ptr %t5, i64 %t6)
  %t8 = call i32 @isdigit(i32 %t7)
  %t9 = icmp ne i32 %t8, 0
  store i1 %t9, ptr %or.val2, align 1
  br i1 %t9, label %or.end2, label %or.rhs2
or.rhs2:
  %t10 = load ptr, ptr %buf.addr, align 8
  %t11 = load i64, ptr %pos.addr, align 8
  %t12 = call i32 @char-at(ptr %t10, i64 %t11)
  %t13 = icmp sge i32 %t12, 65
  store i1 %t13, ptr %and.val4, align 1
  br i1 %t13, label %and.rhs4, label %and.end4
and.rhs4:
  %t14 = load ptr, ptr %buf.addr, align 8
  %t15 = load i64, ptr %pos.addr, align 8
  %t16 = call i32 @char-at(ptr %t14, i64 %t15)
  %t17 = icmp sle i32 %t16, 90
  store i1 %t17, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t18 = load i1, ptr %and.val4, align 1
  store i1 %t18, ptr %or.val3, align 1
  br i1 %t18, label %or.end3, label %or.rhs3
or.rhs3:
  %t19 = load ptr, ptr %buf.addr, align 8
  %t20 = load i64, ptr %pos.addr, align 8
  %t21 = call i32 @char-at(ptr %t19, i64 %t20)
  %t22 = icmp sge i32 %t21, 97
  store i1 %t22, ptr %and.val6, align 1
  br i1 %t22, label %and.rhs6, label %and.end6
and.rhs6:
  %t23 = load ptr, ptr %buf.addr, align 8
  %t24 = load i64, ptr %pos.addr, align 8
  %t25 = call i32 @char-at(ptr %t23, i64 %t24)
  %t26 = icmp sle i32 %t25, 122
  store i1 %t26, ptr %and.val6, align 1
  br label %and.end6
and.end6:
  %t27 = load i1, ptr %and.val6, align 1
  store i1 %t27, ptr %or.val5, align 1
  br i1 %t27, label %or.end5, label %or.rhs5
or.rhs5:
  %t28 = load ptr, ptr %buf.addr, align 8
  %t29 = load i64, ptr %pos.addr, align 8
  %t30 = call i32 @char-at(ptr %t28, i64 %t29)
  %t31 = icmp eq i32 %t30, 95
  store i1 %t31, ptr %or.val5, align 1
  br label %or.end5
or.end5:
  %t32 = load i1, ptr %or.val5, align 1
  store i1 %t32, ptr %or.val3, align 1
  br label %or.end3
or.end3:
  %t33 = load i1, ptr %or.val3, align 1
  store i1 %t33, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t34 = load i1, ptr %or.val2, align 1
  store i1 %t34, ptr %and.val1, align 1
  br label %and.end1
and.end1:
  %t35 = load i1, ptr %and.val1, align 1
  br i1 %t35, label %while.body0, label %while.end0
while.body0:
  %t36 = load i64, ptr %pos.addr, align 8
  %t37 = sext i32 1 to i64
  %t38 = add nsw i64 %t36, %t37
  store i64 %t38, ptr %pos.addr, align 8
  br label %while.cond0
while.end0:
  %t39 = load ptr, ptr %out-end.addr, align 8
  %t40 = load i64, ptr %pos.addr, align 8
  store i64 %t40, ptr %t39, align 8
  %t41 = load ptr, ptr %buf.addr, align 8
  %t42 = load i64, ptr %start.addr.0, align 8
  %t43 = getelementptr inbounds i8, ptr %t41, i64 %t42
  %t44 = load i64, ptr %pos.addr, align 8
  %t45 = load i64, ptr %start.addr.0, align 8
  %t46 = sub nsw i64 %t44, %t45
  %t47 = call ptr @arena-strndup(ptr %t43, i64 %t46)
  ret ptr %t47
}

define ptr @c-type-to-nucleus(ptr %name.arg, i32 %is-unsigned.arg, i32 %is-long.arg, i32 %is-short.arg) {
entry:
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %is-unsigned.addr = alloca i32, align 4
  store i32 %is-unsigned.arg, ptr %is-unsigned.addr, align 4
  %is-long.addr = alloca i32, align 4
  store i32 %is-long.arg, ptr %is-long.addr, align 4
  %is-short.addr = alloca i32, align 4
  store i32 %is-short.arg, ptr %is-short.addr, align 4
  %t0 = load ptr, ptr %name.addr, align 8
  %t1 = getelementptr inbounds [5 x i8], ptr @.str.400, i64 0, i64 0
  %t2 = call i32 @strcmp(ptr %t0, ptr %t1)
  %t3 = icmp eq i32 %t2, 0
  br i1 %t3, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t4 = load ptr, ptr @ty-void, align 8
  ret ptr %t4
cond.end0:
  %t5 = load ptr, ptr %name.addr, align 8
  %t6 = getelementptr inbounds [6 x i8], ptr @.str.401, i64 0, i64 0
  %t7 = call i32 @strcmp(ptr %t5, ptr %t6)
  %t8 = icmp eq i32 %t7, 0
  br i1 %t8, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t9 = load ptr, ptr @ty-i1, align 8
  ret ptr %t9
cond.end1:
  %t10 = load ptr, ptr %name.addr, align 8
  %t11 = getelementptr inbounds [5 x i8], ptr @.str.402, i64 0, i64 0
  %t12 = call i32 @strcmp(ptr %t10, ptr %t11)
  %t13 = icmp eq i32 %t12, 0
  br i1 %t13, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t14 = load i32, ptr %is-unsigned.addr, align 4
  %t15 = icmp ne i32 %t14, 0
  br i1 %t15, label %cond.then3.0, label %cond.test3.1
cond.then3.0:
  %t16 = load ptr, ptr @ty-ui8, align 8
  ret ptr %t16
cond.test3.1:
  br i1 1, label %cond.then3.1, label %cond.end3
cond.then3.1:
  %t17 = load ptr, ptr @ty-i8, align 8
  ret ptr %t17
cond.end3:
  br label %cond.end2
cond.end2:
  %t18 = load ptr, ptr %name.addr, align 8
  %t19 = getelementptr inbounds [6 x i8], ptr @.str.403, i64 0, i64 0
  %t20 = call i32 @strcmp(ptr %t18, ptr %t19)
  %t21 = icmp eq i32 %t20, 0
  br i1 %t21, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t22 = load i32, ptr %is-unsigned.addr, align 4
  %t23 = icmp ne i32 %t22, 0
  br i1 %t23, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t24 = load ptr, ptr @ty-ui16, align 8
  ret ptr %t24
cond.test5.1:
  br i1 1, label %cond.then5.1, label %cond.end5
cond.then5.1:
  %t25 = load ptr, ptr @ty-i16, align 8
  ret ptr %t25
cond.end5:
  br label %cond.end4
cond.end4:
  %t26 = load ptr, ptr %name.addr, align 8
  %t27 = getelementptr inbounds [4 x i8], ptr @.str.404, i64 0, i64 0
  %t28 = call i32 @strcmp(ptr %t26, ptr %t27)
  %t29 = icmp eq i32 %t28, 0
  br i1 %t29, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t30 = load i32, ptr %is-short.addr, align 4
  %t31 = icmp ne i32 %t30, 0
  br i1 %t31, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t32 = load i32, ptr %is-unsigned.addr, align 4
  %t33 = icmp ne i32 %t32, 0
  br i1 %t33, label %cond.then8.0, label %cond.test8.1
cond.then8.0:
  %t34 = load ptr, ptr @ty-ui16, align 8
  ret ptr %t34
cond.test8.1:
  br i1 1, label %cond.then8.1, label %cond.end8
cond.then8.1:
  %t35 = load ptr, ptr @ty-i16, align 8
  ret ptr %t35
cond.end8:
  br label %cond.end7
cond.end7:
  %t36 = load i32, ptr %is-long.addr, align 4
  %t37 = icmp ne i32 %t36, 0
  br i1 %t37, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t38 = load i32, ptr %is-unsigned.addr, align 4
  %t39 = icmp ne i32 %t38, 0
  br i1 %t39, label %cond.then10.0, label %cond.test10.1
cond.then10.0:
  %t40 = load ptr, ptr @ty-ui64, align 8
  ret ptr %t40
cond.test10.1:
  br i1 1, label %cond.then10.1, label %cond.end10
cond.then10.1:
  %t41 = load ptr, ptr @ty-i64, align 8
  ret ptr %t41
cond.end10:
  br label %cond.end9
cond.end9:
  %t42 = load i32, ptr %is-unsigned.addr, align 4
  %t43 = icmp ne i32 %t42, 0
  br i1 %t43, label %cond.then11.0, label %cond.test11.1
cond.then11.0:
  %t44 = load ptr, ptr @ty-ui32, align 8
  ret ptr %t44
cond.test11.1:
  br i1 1, label %cond.then11.1, label %cond.end11
cond.then11.1:
  %t45 = load ptr, ptr @ty-i32, align 8
  ret ptr %t45
cond.end11:
  br label %cond.end6
cond.end6:
  %t46 = load ptr, ptr %name.addr, align 8
  %t47 = getelementptr inbounds [5 x i8], ptr @.str.405, i64 0, i64 0
  %t48 = call i32 @strcmp(ptr %t46, ptr %t47)
  %t49 = icmp eq i32 %t48, 0
  br i1 %t49, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t50 = load i32, ptr %is-unsigned.addr, align 4
  %t51 = icmp ne i32 %t50, 0
  br i1 %t51, label %cond.then13.0, label %cond.test13.1
cond.then13.0:
  %t52 = load ptr, ptr @ty-ui64, align 8
  ret ptr %t52
cond.test13.1:
  br i1 1, label %cond.then13.1, label %cond.end13
cond.then13.1:
  %t53 = load ptr, ptr @ty-i64, align 8
  ret ptr %t53
cond.end13:
  br label %cond.end12
cond.end12:
  %t54 = load ptr, ptr %name.addr, align 8
  %t55 = getelementptr inbounds [7 x i8], ptr @.str.406, i64 0, i64 0
  %t56 = call i32 @strcmp(ptr %t54, ptr %t55)
  %t57 = icmp eq i32 %t56, 0
  br i1 %t57, label %cond.then14.0, label %cond.end14
cond.then14.0:
  %t58 = load ptr, ptr @ty-ui64, align 8
  ret ptr %t58
cond.end14:
  %t59 = load ptr, ptr %name.addr, align 8
  %t60 = getelementptr inbounds [8 x i8], ptr @.str.407, i64 0, i64 0
  %t61 = call i32 @strcmp(ptr %t59, ptr %t60)
  %t62 = icmp eq i32 %t61, 0
  br i1 %t62, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t63 = load ptr, ptr @ty-i64, align 8
  ret ptr %t63
cond.end15:
  %t64 = load ptr, ptr %name.addr, align 8
  %t65 = getelementptr inbounds [15 x i8], ptr @.str.408, i64 0, i64 0
  %t66 = call i32 @strcmp(ptr %t64, ptr %t65)
  %t67 = icmp eq i32 %t66, 0
  br i1 %t67, label %cond.then16.0, label %cond.end16
cond.then16.0:
  %t68 = load ptr, ptr @ty-ptr, align 8
  ret ptr %t68
cond.end16:
  %t69 = load ptr, ptr %name.addr, align 8
  %t70 = getelementptr inbounds [8 x i8], ptr @.str.409, i64 0, i64 0
  %t71 = call i32 @strcmp(ptr %t69, ptr %t70)
  %t72 = icmp eq i32 %t71, 0
  br i1 %t72, label %cond.then17.0, label %cond.end17
cond.then17.0:
  %t73 = load ptr, ptr @ty-ptr, align 8
  ret ptr %t73
cond.end17:
  %t74 = load ptr, ptr %name.addr, align 8
  %t75 = getelementptr inbounds [5 x i8], ptr @.str.410, i64 0, i64 0
  %t76 = call i32 @strcmp(ptr %t74, ptr %t75)
  %t77 = icmp eq i32 %t76, 0
  br i1 %t77, label %cond.then18.0, label %cond.end18
cond.then18.0:
  %t78 = load ptr, ptr @ty-ptr, align 8
  ret ptr %t78
cond.end18:
  ret ptr null
}

define i64 @c-skip-parens(ptr %buf.arg, i64 %pos.arg, i64 %len.arg) {
entry:
  %buf.addr = alloca ptr, align 8
  store ptr %buf.arg, ptr %buf.addr, align 8
  %pos.addr = alloca i64, align 8
  store i64 %pos.arg, ptr %pos.addr, align 8
  %len.addr = alloca i64, align 8
  store i64 %len.arg, ptr %len.addr, align 8
  %depth.addr.0 = alloca i32, align 4
  store i32 0, ptr %depth.addr.0, align 4
  br label %while.cond0
while.cond0:
  %t1 = load i64, ptr %pos.addr, align 8
  %t2 = load i64, ptr %len.addr, align 8
  %t3 = icmp slt i64 %t1, %t2
  br i1 %t3, label %while.body0, label %while.end0
while.body0:
  %t4 = load ptr, ptr %buf.addr, align 8
  %t5 = load i64, ptr %pos.addr, align 8
  %t6 = call i32 @char-at(ptr %t4, i64 %t5)
  %t7 = icmp eq i32 %t6, 40
  br i1 %t7, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t8 = load i32, ptr %depth.addr.0, align 4
  %t9 = add nsw i32 %t8, 1
  store i32 %t9, ptr %depth.addr.0, align 4
  br label %cond.end1
cond.end1:
  %t10 = load ptr, ptr %buf.addr, align 8
  %t11 = load i64, ptr %pos.addr, align 8
  %t12 = call i32 @char-at(ptr %t10, i64 %t11)
  %t13 = icmp eq i32 %t12, 41
  br i1 %t13, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t14 = load i32, ptr %depth.addr.0, align 4
  %t15 = sub nsw i32 %t14, 1
  store i32 %t15, ptr %depth.addr.0, align 4
  %t16 = load i32, ptr %depth.addr.0, align 4
  %t17 = icmp eq i32 %t16, 0
  br i1 %t17, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t18 = load i64, ptr %pos.addr, align 8
  %t19 = sext i32 1 to i64
  %t20 = add nsw i64 %t18, %t19
  ret i64 %t20
cond.end3:
  br label %cond.end2
cond.end2:
  %t21 = load i64, ptr %pos.addr, align 8
  %t22 = sext i32 1 to i64
  %t23 = add nsw i64 %t21, %t22
  store i64 %t23, ptr %pos.addr, align 8
  br label %while.cond0
while.end0:
  %t24 = load i64, ptr %pos.addr, align 8
  ret i64 %t24
}

define ptr @c-parse-type(ptr %buf.arg, i64 %pos.arg, i64 %len.arg, ptr %out-end.arg) {
entry:
  %buf.addr = alloca ptr, align 8
  store ptr %buf.arg, ptr %buf.addr, align 8
  %pos.addr = alloca i64, align 8
  store i64 %pos.arg, ptr %pos.addr, align 8
  %len.addr = alloca i64, align 8
  store i64 %len.arg, ptr %len.addr, align 8
  %out-end.addr = alloca ptr, align 8
  store ptr %out-end.arg, ptr %out-end.addr, align 8
  %is-unsigned.addr.0 = alloca i32, align 4
  %is-long.addr.1 = alloca i32, align 4
  %is-short.addr.2 = alloca i32, align 4
  %base-name.addr.3 = alloca ptr, align 8
  %ptr-depth.addr.4 = alloca i32, align 4
  %is-struct.addr.5 = alloca i32, align 4
  %done.addr.6 = alloca i32, align 4
  %tok-end.addr.19 = alloca i64, align 8
  %tok.addr.21 = alloca ptr, align 8
  %peek-pos.addr.102 = alloca i64, align 8
  %peek-end.addr.107 = alloca i64, align 8
  %peek-tok.addr.109 = alloca ptr, align 8
  %and.val8 = alloca i1, align 1
  %and.val9 = alloca i1, align 1
  %and.val11 = alloca i1, align 1
  %and.val13 = alloca i1, align 1
  %check.addr.187 = alloca i32, align 4
  %te.addr.190 = alloca i64, align 8
  %t.addr.192 = alloca ptr, align 8
  %or.val16 = alloca i1, align 1
  %or.val17 = alloca i1, align 1
  %or.val21 = alloca i1, align 1
  %or.val22 = alloca i1, align 1
  %base-type.addr.235 = alloca ptr, align 8
  store i32 0, ptr %is-unsigned.addr.0, align 4
  store i32 0, ptr %is-long.addr.1, align 4
  store i32 0, ptr %is-short.addr.2, align 4
  store ptr null, ptr %base-name.addr.3, align 8
  store i32 0, ptr %ptr-depth.addr.4, align 4
  store i32 0, ptr %is-struct.addr.5, align 4
  store i32 0, ptr %done.addr.6, align 4
  br label %while.cond0
while.cond0:
  %t7 = load i32, ptr %done.addr.6, align 4
  %t8 = icmp eq i32 %t7, 0
  br i1 %t8, label %while.body0, label %while.end0
while.body0:
  %t9 = load ptr, ptr %buf.addr, align 8
  %t10 = load i64, ptr %pos.addr, align 8
  %t11 = load i64, ptr %len.addr, align 8
  %t12 = call i64 @c-skip-ws(ptr %t9, i64 %t10, i64 %t11)
  store i64 %t12, ptr %pos.addr, align 8
  %t13 = load i64, ptr %pos.addr, align 8
  %t14 = load i64, ptr %len.addr, align 8
  %t15 = icmp sge i64 %t13, %t14
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  store i32 1, ptr %done.addr.6, align 4
  %t16 = load i64, ptr %len.addr, align 8
  store i64 %t16, ptr %pos.addr, align 8
  br label %cond.end1
cond.end1:
  %t17 = load i32, ptr %done.addr.6, align 4
  %t18 = icmp eq i32 %t17, 0
  br i1 %t18, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t20 = sext i32 0 to i64
  store i64 %t20, ptr %tok-end.addr.19, align 8
  %t22 = load ptr, ptr %buf.addr, align 8
  %t23 = load i64, ptr %pos.addr, align 8
  %t24 = load i64, ptr %len.addr, align 8
  %t25 = call ptr @c-read-ident(ptr %t22, i64 %t23, i64 %t24, ptr %tok-end.addr.19)
  store ptr %t25, ptr %tok.addr.21, align 8
  %t26 = load ptr, ptr %tok.addr.21, align 8
  %t27 = call i64 @strlen(ptr %t26)
  %t28 = sext i32 0 to i64
  %t29 = icmp eq i64 %t27, %t28
  br i1 %t29, label %cond.then3.0, label %cond.end3
cond.then3.0:
  store i32 1, ptr %done.addr.6, align 4
  br label %cond.end3
cond.end3:
  %t30 = load i32, ptr %done.addr.6, align 4
  %t31 = icmp eq i32 %t30, 0
  br i1 %t31, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t32 = load ptr, ptr %tok.addr.21, align 8
  %t33 = getelementptr inbounds [6 x i8], ptr @.str.411, i64 0, i64 0
  %t34 = call i32 @strcmp(ptr %t32, ptr %t33)
  %t35 = icmp eq i32 %t34, 0
  br i1 %t35, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t36 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t36, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.1:
  %t37 = load ptr, ptr %tok.addr.21, align 8
  %t38 = getelementptr inbounds [9 x i8], ptr @.str.412, i64 0, i64 0
  %t39 = call i32 @strcmp(ptr %t37, ptr %t38)
  %t40 = icmp eq i32 %t39, 0
  br i1 %t40, label %cond.then5.1, label %cond.test5.2
cond.then5.1:
  %t41 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t41, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.2:
  %t42 = load ptr, ptr %tok.addr.21, align 8
  %t43 = getelementptr inbounds [9 x i8], ptr @.str.413, i64 0, i64 0
  %t44 = call i32 @strcmp(ptr %t42, ptr %t43)
  %t45 = icmp eq i32 %t44, 0
  br i1 %t45, label %cond.then5.2, label %cond.test5.3
cond.then5.2:
  %t46 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t46, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.3:
  %t47 = load ptr, ptr %tok.addr.21, align 8
  %t48 = getelementptr inbounds [11 x i8], ptr @.str.414, i64 0, i64 0
  %t49 = call i32 @strcmp(ptr %t47, ptr %t48)
  %t50 = icmp eq i32 %t49, 0
  br i1 %t50, label %cond.then5.3, label %cond.test5.4
cond.then5.3:
  %t51 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t51, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.4:
  %t52 = load ptr, ptr %tok.addr.21, align 8
  %t53 = getelementptr inbounds [8 x i8], ptr @.str.415, i64 0, i64 0
  %t54 = call i32 @strcmp(ptr %t52, ptr %t53)
  %t55 = icmp eq i32 %t54, 0
  br i1 %t55, label %cond.then5.4, label %cond.test5.5
cond.then5.4:
  %t56 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t56, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.5:
  %t57 = load ptr, ptr %tok.addr.21, align 8
  %t58 = getelementptr inbounds [7 x i8], ptr @.str.416, i64 0, i64 0
  %t59 = call i32 @strcmp(ptr %t57, ptr %t58)
  %t60 = icmp eq i32 %t59, 0
  br i1 %t60, label %cond.then5.5, label %cond.test5.6
cond.then5.5:
  %t61 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t61, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.6:
  %t62 = load ptr, ptr %tok.addr.21, align 8
  %t63 = getelementptr inbounds [7 x i8], ptr @.str.417, i64 0, i64 0
  %t64 = call i32 @strcmp(ptr %t62, ptr %t63)
  %t65 = icmp eq i32 %t64, 0
  br i1 %t65, label %cond.then5.6, label %cond.test5.7
cond.then5.6:
  %t66 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t66, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.7:
  %t67 = load ptr, ptr %tok.addr.21, align 8
  %t68 = getelementptr inbounds [7 x i8], ptr @.str.418, i64 0, i64 0
  %t69 = call i32 @strcmp(ptr %t67, ptr %t68)
  %t70 = icmp eq i32 %t69, 0
  br i1 %t70, label %cond.then5.7, label %cond.test5.8
cond.then5.7:
  %t71 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t71, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.8:
  %t72 = load ptr, ptr %tok.addr.21, align 8
  %t73 = getelementptr inbounds [9 x i8], ptr @.str.419, i64 0, i64 0
  %t74 = call i32 @strcmp(ptr %t72, ptr %t73)
  %t75 = icmp eq i32 %t74, 0
  br i1 %t75, label %cond.then5.8, label %cond.test5.9
cond.then5.8:
  %t76 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t76, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.9:
  %t77 = load ptr, ptr %tok.addr.21, align 8
  %t78 = getelementptr inbounds [11 x i8], ptr @.str.420, i64 0, i64 0
  %t79 = call i32 @strcmp(ptr %t77, ptr %t78)
  %t80 = icmp eq i32 %t79, 0
  br i1 %t80, label %cond.then5.9, label %cond.test5.10
cond.then5.9:
  %t81 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t81, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.10:
  %t82 = load ptr, ptr %tok.addr.21, align 8
  %t83 = getelementptr inbounds [14 x i8], ptr @.str.421, i64 0, i64 0
  %t84 = call i32 @strcmp(ptr %t82, ptr %t83)
  %t85 = icmp eq i32 %t84, 0
  br i1 %t85, label %cond.then5.10, label %cond.test5.11
cond.then5.10:
  %t86 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t86, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.11:
  %t87 = load ptr, ptr %tok.addr.21, align 8
  %t88 = getelementptr inbounds [9 x i8], ptr @.str.422, i64 0, i64 0
  %t89 = call i32 @strcmp(ptr %t87, ptr %t88)
  %t90 = icmp eq i32 %t89, 0
  br i1 %t90, label %cond.then5.11, label %cond.test5.12
cond.then5.11:
  store i32 1, ptr %is-unsigned.addr.0, align 4
  %t91 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t91, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.12:
  %t92 = load ptr, ptr %tok.addr.21, align 8
  %t93 = getelementptr inbounds [7 x i8], ptr @.str.423, i64 0, i64 0
  %t94 = call i32 @strcmp(ptr %t92, ptr %t93)
  %t95 = icmp eq i32 %t94, 0
  br i1 %t95, label %cond.then5.12, label %cond.test5.13
cond.then5.12:
  %t96 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t96, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.13:
  %t97 = load ptr, ptr %tok.addr.21, align 8
  %t98 = getelementptr inbounds [5 x i8], ptr @.str.424, i64 0, i64 0
  %t99 = call i32 @strcmp(ptr %t97, ptr %t98)
  %t100 = icmp eq i32 %t99, 0
  br i1 %t100, label %cond.then5.13, label %cond.test5.14
cond.then5.13:
  store i32 1, ptr %is-long.addr.1, align 4
  %t101 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t101, ptr %pos.addr, align 8
  %t103 = load ptr, ptr %buf.addr, align 8
  %t104 = load i64, ptr %tok-end.addr.19, align 8
  %t105 = load i64, ptr %len.addr, align 8
  %t106 = call i64 @c-skip-ws(ptr %t103, i64 %t104, i64 %t105)
  store i64 %t106, ptr %peek-pos.addr.102, align 8
  %t108 = sext i32 0 to i64
  store i64 %t108, ptr %peek-end.addr.107, align 8
  %t110 = load ptr, ptr %buf.addr, align 8
  %t111 = load i64, ptr %peek-pos.addr.102, align 8
  %t112 = load i64, ptr %len.addr, align 8
  %t113 = call ptr @c-read-ident(ptr %t110, i64 %t111, i64 %t112, ptr %peek-end.addr.107)
  store ptr %t113, ptr %peek-tok.addr.109, align 8
  %t114 = load ptr, ptr %peek-tok.addr.109, align 8
  %t115 = getelementptr inbounds [5 x i8], ptr @.str.425, i64 0, i64 0
  %t116 = call i32 @strcmp(ptr %t114, ptr %t115)
  %t117 = icmp eq i32 %t116, 0
  br i1 %t117, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t118 = load i64, ptr %peek-end.addr.107, align 8
  store i64 %t118, ptr %pos.addr, align 8
  br label %cond.end6
cond.end6:
  %t119 = load ptr, ptr %peek-tok.addr.109, align 8
  %t120 = getelementptr inbounds [4 x i8], ptr @.str.426, i64 0, i64 0
  %t121 = call i32 @strcmp(ptr %t119, ptr %t120)
  %t122 = icmp ne i32 %t121, 0
  store i1 %t122, ptr %and.val8, align 1
  br i1 %t122, label %and.rhs8, label %and.end8
and.rhs8:
  %t123 = load ptr, ptr %peek-tok.addr.109, align 8
  %t124 = getelementptr inbounds [5 x i8], ptr @.str.427, i64 0, i64 0
  %t125 = call i32 @strcmp(ptr %t123, ptr %t124)
  %t126 = icmp ne i32 %t125, 0
  store i1 %t126, ptr %and.val9, align 1
  br i1 %t126, label %and.rhs9, label %and.end9
and.rhs9:
  %t127 = load ptr, ptr %peek-tok.addr.109, align 8
  %t128 = getelementptr inbounds [5 x i8], ptr @.str.428, i64 0, i64 0
  %t129 = call i32 @strcmp(ptr %t127, ptr %t128)
  %t130 = icmp ne i32 %t129, 0
  store i1 %t130, ptr %and.val9, align 1
  br label %and.end9
and.end9:
  %t131 = load i1, ptr %and.val9, align 1
  store i1 %t131, ptr %and.val8, align 1
  br label %and.end8
and.end8:
  %t132 = load i1, ptr %and.val8, align 1
  br i1 %t132, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t133 = getelementptr inbounds [5 x i8], ptr @.str.429, i64 0, i64 0
  store ptr %t133, ptr %base-name.addr.3, align 8
  store i32 1, ptr %done.addr.6, align 4
  br label %cond.end7
cond.end7:
  br label %cond.end5
cond.test5.14:
  %t134 = load ptr, ptr %tok.addr.21, align 8
  %t135 = getelementptr inbounds [6 x i8], ptr @.str.430, i64 0, i64 0
  %t136 = call i32 @strcmp(ptr %t134, ptr %t135)
  %t137 = icmp eq i32 %t136, 0
  br i1 %t137, label %cond.then5.14, label %cond.test5.15
cond.then5.14:
  store i32 1, ptr %is-short.addr.2, align 4
  %t138 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t138, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.15:
  %t139 = load ptr, ptr %tok.addr.21, align 8
  %t140 = getelementptr inbounds [7 x i8], ptr @.str.431, i64 0, i64 0
  %t141 = call i32 @strcmp(ptr %t139, ptr %t140)
  %t142 = icmp eq i32 %t141, 0
  br i1 %t142, label %cond.then5.15, label %cond.test5.16
cond.then5.15:
  store i32 1, ptr %is-struct.addr.5, align 4
  %t143 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t143, ptr %pos.addr, align 8
  br label %cond.end5
cond.test5.16:
  %t144 = load ptr, ptr %tok.addr.21, align 8
  %t145 = getelementptr inbounds [14 x i8], ptr @.str.432, i64 0, i64 0
  %t146 = call i32 @strcmp(ptr %t144, ptr %t145)
  %t147 = icmp eq i32 %t146, 0
  br i1 %t147, label %cond.then5.16, label %cond.test5.17
cond.then5.16:
  %t148 = load ptr, ptr %buf.addr, align 8
  %t149 = load i64, ptr %tok-end.addr.19, align 8
  %t150 = load i64, ptr %len.addr, align 8
  %t151 = call i64 @c-skip-ws(ptr %t148, i64 %t149, i64 %t150)
  store i64 %t151, ptr %pos.addr, align 8
  %t152 = load i64, ptr %pos.addr, align 8
  %t153 = load i64, ptr %len.addr, align 8
  %t154 = icmp slt i64 %t152, %t153
  store i1 %t154, ptr %and.val11, align 1
  br i1 %t154, label %and.rhs11, label %and.end11
and.rhs11:
  %t155 = load ptr, ptr %buf.addr, align 8
  %t156 = load i64, ptr %pos.addr, align 8
  %t157 = call i32 @char-at(ptr %t155, i64 %t156)
  %t158 = icmp eq i32 %t157, 40
  store i1 %t158, ptr %and.val11, align 1
  br label %and.end11
and.end11:
  %t159 = load i1, ptr %and.val11, align 1
  br i1 %t159, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t160 = load ptr, ptr %buf.addr, align 8
  %t161 = load i64, ptr %pos.addr, align 8
  %t162 = load i64, ptr %len.addr, align 8
  %t163 = call i64 @c-skip-parens(ptr %t160, i64 %t161, i64 %t162)
  store i64 %t163, ptr %pos.addr, align 8
  br label %cond.end10
cond.end10:
  br label %cond.end5
cond.test5.17:
  br i1 1, label %cond.then5.17, label %cond.end5
cond.then5.17:
  %t164 = load ptr, ptr %tok.addr.21, align 8
  store ptr %t164, ptr %base-name.addr.3, align 8
  %t165 = load i64, ptr %tok-end.addr.19, align 8
  store i64 %t165, ptr %pos.addr, align 8
  store i32 1, ptr %done.addr.6, align 4
  br label %cond.end5
cond.end5:
  br label %cond.end4
cond.end4:
  br label %cond.end2
cond.end2:
  br label %while.cond0
while.end0:
  %t166 = load ptr, ptr %buf.addr, align 8
  %t167 = load i64, ptr %pos.addr, align 8
  %t168 = load i64, ptr %len.addr, align 8
  %t169 = call i64 @c-skip-ws(ptr %t166, i64 %t167, i64 %t168)
  store i64 %t169, ptr %pos.addr, align 8
  br label %while.cond12
while.cond12:
  %t170 = load i64, ptr %pos.addr, align 8
  %t171 = load i64, ptr %len.addr, align 8
  %t172 = icmp slt i64 %t170, %t171
  store i1 %t172, ptr %and.val13, align 1
  br i1 %t172, label %and.rhs13, label %and.end13
and.rhs13:
  %t173 = load ptr, ptr %buf.addr, align 8
  %t174 = load i64, ptr %pos.addr, align 8
  %t175 = call i32 @char-at(ptr %t173, i64 %t174)
  %t176 = icmp eq i32 %t175, 42
  store i1 %t176, ptr %and.val13, align 1
  br label %and.end13
and.end13:
  %t177 = load i1, ptr %and.val13, align 1
  br i1 %t177, label %while.body12, label %while.end12
while.body12:
  %t178 = load i32, ptr %ptr-depth.addr.4, align 4
  %t179 = add nsw i32 %t178, 1
  store i32 %t179, ptr %ptr-depth.addr.4, align 4
  %t180 = load i64, ptr %pos.addr, align 8
  %t181 = sext i32 1 to i64
  %t182 = add nsw i64 %t180, %t181
  store i64 %t182, ptr %pos.addr, align 8
  %t183 = load ptr, ptr %buf.addr, align 8
  %t184 = load i64, ptr %pos.addr, align 8
  %t185 = load i64, ptr %len.addr, align 8
  %t186 = call i64 @c-skip-ws(ptr %t183, i64 %t184, i64 %t185)
  store i64 %t186, ptr %pos.addr, align 8
  store i32 1, ptr %check.addr.187, align 4
  br label %while.cond14
while.cond14:
  %t188 = load i32, ptr %check.addr.187, align 4
  %t189 = icmp ne i32 %t188, 0
  br i1 %t189, label %while.body14, label %while.end14
while.body14:
  store i32 0, ptr %check.addr.187, align 4
  %t191 = sext i32 0 to i64
  store i64 %t191, ptr %te.addr.190, align 8
  %t193 = load ptr, ptr %buf.addr, align 8
  %t194 = load i64, ptr %pos.addr, align 8
  %t195 = load i64, ptr %len.addr, align 8
  %t196 = call ptr @c-read-ident(ptr %t193, i64 %t194, i64 %t195, ptr %te.addr.190)
  store ptr %t196, ptr %t.addr.192, align 8
  %t197 = load ptr, ptr %t.addr.192, align 8
  %t198 = getelementptr inbounds [6 x i8], ptr @.str.433, i64 0, i64 0
  %t199 = call i32 @strcmp(ptr %t197, ptr %t198)
  %t200 = icmp eq i32 %t199, 0
  store i1 %t200, ptr %or.val16, align 1
  br i1 %t200, label %or.end16, label %or.rhs16
or.rhs16:
  %t201 = load ptr, ptr %t.addr.192, align 8
  %t202 = getelementptr inbounds [9 x i8], ptr @.str.434, i64 0, i64 0
  %t203 = call i32 @strcmp(ptr %t201, ptr %t202)
  %t204 = icmp eq i32 %t203, 0
  store i1 %t204, ptr %or.val17, align 1
  br i1 %t204, label %or.end17, label %or.rhs17
or.rhs17:
  %t205 = load ptr, ptr %t.addr.192, align 8
  %t206 = getelementptr inbounds [11 x i8], ptr @.str.435, i64 0, i64 0
  %t207 = call i32 @strcmp(ptr %t205, ptr %t206)
  %t208 = icmp eq i32 %t207, 0
  store i1 %t208, ptr %or.val17, align 1
  br label %or.end17
or.end17:
  %t209 = load i1, ptr %or.val17, align 1
  store i1 %t209, ptr %or.val16, align 1
  br label %or.end16
or.end16:
  %t210 = load i1, ptr %or.val16, align 1
  br i1 %t210, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t211 = load i64, ptr %te.addr.190, align 8
  store i64 %t211, ptr %pos.addr, align 8
  %t212 = load ptr, ptr %buf.addr, align 8
  %t213 = load i64, ptr %pos.addr, align 8
  %t214 = load i64, ptr %len.addr, align 8
  %t215 = call i64 @c-skip-ws(ptr %t212, i64 %t213, i64 %t214)
  store i64 %t215, ptr %pos.addr, align 8
  store i32 1, ptr %check.addr.187, align 4
  br label %cond.end15
cond.end15:
  br label %while.cond14
while.end14:
  br label %while.cond12
while.end12:
  %t216 = load ptr, ptr %out-end.addr, align 8
  %t217 = load i64, ptr %pos.addr, align 8
  store i64 %t217, ptr %t216, align 8
  %t218 = load i32, ptr %is-struct.addr.5, align 4
  %t219 = icmp ne i32 %t218, 0
  br i1 %t219, label %cond.then18.0, label %cond.end18
cond.then18.0:
  %t220 = load ptr, ptr @ty-ptr, align 8
  ret ptr %t220
cond.end18:
  %t221 = load ptr, ptr %base-name.addr.3, align 8
  %t222 = icmp eq ptr %t221, null
  br i1 %t222, label %cond.then19.0, label %cond.end19
cond.then19.0:
  %t223 = load i32, ptr %is-unsigned.addr.0, align 4
  %t224 = icmp ne i32 %t223, 0
  store i1 %t224, ptr %or.val21, align 1
  br i1 %t224, label %or.end21, label %or.rhs21
or.rhs21:
  %t225 = load i32, ptr %is-short.addr.2, align 4
  %t226 = icmp ne i32 %t225, 0
  store i1 %t226, ptr %or.val22, align 1
  br i1 %t226, label %or.end22, label %or.rhs22
or.rhs22:
  %t227 = load i32, ptr %is-long.addr.1, align 4
  %t228 = icmp ne i32 %t227, 0
  store i1 %t228, ptr %or.val22, align 1
  br label %or.end22
or.end22:
  %t229 = load i1, ptr %or.val22, align 1
  store i1 %t229, ptr %or.val21, align 1
  br label %or.end21
or.end21:
  %t230 = load i1, ptr %or.val21, align 1
  br i1 %t230, label %cond.then20.0, label %cond.end20
cond.then20.0:
  %t231 = getelementptr inbounds [4 x i8], ptr @.str.436, i64 0, i64 0
  store ptr %t231, ptr %base-name.addr.3, align 8
  br label %cond.end20
cond.end20:
  %t232 = load ptr, ptr %base-name.addr.3, align 8
  %t233 = icmp eq ptr %t232, null
  br i1 %t233, label %cond.then23.0, label %cond.end23
cond.then23.0:
  %t234 = load ptr, ptr @ty-ptr, align 8
  ret ptr %t234
cond.end23:
  br label %cond.end19
cond.end19:
  %t236 = load ptr, ptr %base-name.addr.3, align 8
  %t237 = load i32, ptr %is-unsigned.addr.0, align 4
  %t238 = load i32, ptr %is-long.addr.1, align 4
  %t239 = load i32, ptr %is-short.addr.2, align 4
  %t240 = call ptr @c-type-to-nucleus(ptr %t236, i32 %t237, i32 %t238, i32 %t239)
  store ptr %t240, ptr %base-type.addr.235, align 8
  %t241 = load ptr, ptr %base-type.addr.235, align 8
  %t242 = icmp eq ptr %t241, null
  br i1 %t242, label %cond.then24.0, label %cond.end24
cond.then24.0:
  %t243 = load ptr, ptr @ty-ptr, align 8
  store ptr %t243, ptr %base-type.addr.235, align 8
  br label %cond.end24
cond.end24:
  %t244 = load i32, ptr %ptr-depth.addr.4, align 4
  %t245 = icmp sgt i32 %t244, 0
  br i1 %t245, label %cond.then25.0, label %cond.end25
cond.then25.0:
  %t246 = load ptr, ptr @ty-ptr, align 8
  ret ptr %t246
cond.end25:
  %t247 = load ptr, ptr %base-type.addr.235, align 8
  ret ptr %t247
}

define i32 @c-parse-func-decl(ptr %buf.arg, i64 %pos.arg, i64 %len.arg, ptr %out-end.arg, i32 %line.arg) {
entry:
  %buf.addr = alloca ptr, align 8
  store ptr %buf.arg, ptr %buf.addr, align 8
  %pos.addr = alloca i64, align 8
  store i64 %pos.arg, ptr %pos.addr, align 8
  %len.addr = alloca i64, align 8
  store i64 %len.arg, ptr %len.addr, align 8
  %out-end.addr = alloca ptr, align 8
  store ptr %out-end.arg, ptr %out-end.addr, align 8
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %ret-end.addr.0 = alloca i64, align 8
  %ret-type.addr.2 = alloca ptr, align 8
  %name-end.addr.12 = alloca i64, align 8
  %fname.addr.14 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %param-types.addr.43 = alloca ptr, align 8
  %num-params.addr.48 = alloca i32, align 4
  %is-variadic.addr.49 = alloca i32, align 4
  %pdone.addr.50 = alloca i32, align 4
  %and.val9 = alloca i1, align 1
  %and.val10 = alloca i1, align 1
  %and.val11 = alloca i1, align 1
  %and.val13 = alloca i1, align 1
  %void-check-end.addr.115 = alloca i64, align 8
  %void-check.addr.117 = alloca ptr, align 8
  %after-void.addr.126 = alloca i64, align 8
  %and.val17 = alloca i1, align 1
  %ptype-end.addr.144 = alloca i64, align 8
  %ptype.addr.146 = alloca ptr, align 8
  %and.val20 = alloca i1, align 1
  %and.val22 = alloca i1, align 1
  %and.val24 = alloca i1, align 1
  %or.val25 = alloca i1, align 1
  %and.val26 = alloca i1, align 1
  %or.val27 = alloca i1, align 1
  %and.val28 = alloca i1, align 1
  %skip-end.addr.213 = alloca i64, align 8
  %skip.addr.215 = alloca ptr, align 8
  %and.val30 = alloca i1, align 1
  %and.val32 = alloca i1, align 1
  %and.val36 = alloca i1, align 1
  %attr-check.addr.283 = alloca i32, align 4
  %ae.addr.286 = alloca i64, align 8
  %at.addr.288 = alloca ptr, align 8
  %and.val40 = alloca i1, align 1
  %and.val43 = alloca i1, align 1
  %and.val45 = alloca i1, align 1
  %ft.addr.354 = alloca ptr, align 8
  %j.addr.369 = alloca i32, align 4
  %j.addr.410 = alloca i32, align 4
  %sep.addr.434 = alloca ptr, align 8
  %t1 = sext i32 0 to i64
  store i64 %t1, ptr %ret-end.addr.0, align 8
  %t3 = load ptr, ptr %buf.addr, align 8
  %t4 = load i64, ptr %pos.addr, align 8
  %t5 = load i64, ptr %len.addr, align 8
  %t6 = call ptr @c-parse-type(ptr %t3, i64 %t4, i64 %t5, ptr %ret-end.addr.0)
  store ptr %t6, ptr %ret-type.addr.2, align 8
  %t7 = load i64, ptr %ret-end.addr.0, align 8
  store i64 %t7, ptr %pos.addr, align 8
  %t8 = load ptr, ptr %buf.addr, align 8
  %t9 = load i64, ptr %pos.addr, align 8
  %t10 = load i64, ptr %len.addr, align 8
  %t11 = call i64 @c-skip-ws(ptr %t8, i64 %t9, i64 %t10)
  store i64 %t11, ptr %pos.addr, align 8
  %t13 = sext i32 0 to i64
  store i64 %t13, ptr %name-end.addr.12, align 8
  %t15 = load ptr, ptr %buf.addr, align 8
  %t16 = load i64, ptr %pos.addr, align 8
  %t17 = load i64, ptr %len.addr, align 8
  %t18 = call ptr @c-read-ident(ptr %t15, i64 %t16, i64 %t17, ptr %name-end.addr.12)
  store ptr %t18, ptr %fname.addr.14, align 8
  %t19 = load ptr, ptr %fname.addr.14, align 8
  %t20 = call i64 @strlen(ptr %t19)
  %t21 = sext i32 0 to i64
  %t22 = icmp eq i64 %t20, %t21
  br i1 %t22, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t23 = load ptr, ptr %out-end.addr, align 8
  %t24 = load i64, ptr %pos.addr, align 8
  store i64 %t24, ptr %t23, align 8
  ret i32 0
cond.end0:
  %t25 = load i64, ptr %name-end.addr.12, align 8
  store i64 %t25, ptr %pos.addr, align 8
  %t26 = load ptr, ptr %buf.addr, align 8
  %t27 = load i64, ptr %pos.addr, align 8
  %t28 = load i64, ptr %len.addr, align 8
  %t29 = call i64 @c-skip-ws(ptr %t26, i64 %t27, i64 %t28)
  store i64 %t29, ptr %pos.addr, align 8
  %t30 = load i64, ptr %pos.addr, align 8
  %t31 = load i64, ptr %len.addr, align 8
  %t32 = icmp sge i64 %t30, %t31
  store i1 %t32, ptr %or.val2, align 1
  br i1 %t32, label %or.end2, label %or.rhs2
or.rhs2:
  %t33 = load ptr, ptr %buf.addr, align 8
  %t34 = load i64, ptr %pos.addr, align 8
  %t35 = call i32 @char-at(ptr %t33, i64 %t34)
  %t36 = icmp ne i32 %t35, 40
  store i1 %t36, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t37 = load i1, ptr %or.val2, align 1
  br i1 %t37, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t38 = load ptr, ptr %out-end.addr, align 8
  %t39 = load i64, ptr %pos.addr, align 8
  store i64 %t39, ptr %t38, align 8
  ret i32 0
cond.end1:
  %t40 = load i64, ptr %pos.addr, align 8
  %t41 = sext i32 1 to i64
  %t42 = add nsw i64 %t40, %t41
  store i64 %t42, ptr %pos.addr, align 8
  %t44 = sext i32 16 to i64
  %t45 = sext i32 8 to i64
  %t46 = mul nsw i64 %t44, %t45
  %t47 = call ptr @arena-alloc(i64 %t46)
  store ptr %t47, ptr %param-types.addr.43, align 8
  store i32 0, ptr %num-params.addr.48, align 4
  store i32 0, ptr %is-variadic.addr.49, align 4
  store i32 0, ptr %pdone.addr.50, align 4
  br label %while.cond3
while.cond3:
  %t51 = load i32, ptr %pdone.addr.50, align 4
  %t52 = icmp eq i32 %t51, 0
  br i1 %t52, label %while.body3, label %while.end3
while.body3:
  %t53 = load ptr, ptr %buf.addr, align 8
  %t54 = load i64, ptr %pos.addr, align 8
  %t55 = load i64, ptr %len.addr, align 8
  %t56 = call i64 @c-skip-ws(ptr %t53, i64 %t54, i64 %t55)
  store i64 %t56, ptr %pos.addr, align 8
  %t57 = load i64, ptr %pos.addr, align 8
  %t58 = load i64, ptr %len.addr, align 8
  %t59 = icmp sge i64 %t57, %t58
  br i1 %t59, label %cond.then4.0, label %cond.end4
cond.then4.0:
  store i32 1, ptr %pdone.addr.50, align 4
  br label %cond.end4
cond.end4:
  %t60 = load i32, ptr %pdone.addr.50, align 4
  %t61 = icmp eq i32 %t60, 0
  br i1 %t61, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t62 = load ptr, ptr %buf.addr, align 8
  %t63 = load i64, ptr %pos.addr, align 8
  %t64 = call i32 @char-at(ptr %t62, i64 %t63)
  %t65 = icmp eq i32 %t64, 41
  br i1 %t65, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t66 = load i64, ptr %pos.addr, align 8
  %t67 = sext i32 1 to i64
  %t68 = add nsw i64 %t66, %t67
  store i64 %t68, ptr %pos.addr, align 8
  store i32 1, ptr %pdone.addr.50, align 4
  br label %cond.end6
cond.end6:
  %t69 = load i32, ptr %pdone.addr.50, align 4
  %t70 = icmp eq i32 %t69, 0
  br i1 %t70, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t71 = load i64, ptr %pos.addr, align 8
  %t72 = sext i32 2 to i64
  %t73 = add nsw i64 %t71, %t72
  %t74 = load i64, ptr %len.addr, align 8
  %t75 = icmp slt i64 %t73, %t74
  store i1 %t75, ptr %and.val9, align 1
  br i1 %t75, label %and.rhs9, label %and.end9
and.rhs9:
  %t76 = load ptr, ptr %buf.addr, align 8
  %t77 = load i64, ptr %pos.addr, align 8
  %t78 = call i32 @char-at(ptr %t76, i64 %t77)
  %t79 = icmp eq i32 %t78, 46
  store i1 %t79, ptr %and.val10, align 1
  br i1 %t79, label %and.rhs10, label %and.end10
and.rhs10:
  %t80 = load ptr, ptr %buf.addr, align 8
  %t81 = load i64, ptr %pos.addr, align 8
  %t82 = sext i32 1 to i64
  %t83 = add nsw i64 %t81, %t82
  %t84 = call i32 @char-at(ptr %t80, i64 %t83)
  %t85 = icmp eq i32 %t84, 46
  store i1 %t85, ptr %and.val11, align 1
  br i1 %t85, label %and.rhs11, label %and.end11
and.rhs11:
  %t86 = load ptr, ptr %buf.addr, align 8
  %t87 = load i64, ptr %pos.addr, align 8
  %t88 = sext i32 2 to i64
  %t89 = add nsw i64 %t87, %t88
  %t90 = call i32 @char-at(ptr %t86, i64 %t89)
  %t91 = icmp eq i32 %t90, 46
  store i1 %t91, ptr %and.val11, align 1
  br label %and.end11
and.end11:
  %t92 = load i1, ptr %and.val11, align 1
  store i1 %t92, ptr %and.val10, align 1
  br label %and.end10
and.end10:
  %t93 = load i1, ptr %and.val10, align 1
  store i1 %t93, ptr %and.val9, align 1
  br label %and.end9
and.end9:
  %t94 = load i1, ptr %and.val9, align 1
  br i1 %t94, label %cond.then8.0, label %cond.end8
cond.then8.0:
  store i32 1, ptr %is-variadic.addr.49, align 4
  %t95 = load i64, ptr %pos.addr, align 8
  %t96 = sext i32 3 to i64
  %t97 = add nsw i64 %t95, %t96
  store i64 %t97, ptr %pos.addr, align 8
  %t98 = load ptr, ptr %buf.addr, align 8
  %t99 = load i64, ptr %pos.addr, align 8
  %t100 = load i64, ptr %len.addr, align 8
  %t101 = call i64 @c-skip-ws(ptr %t98, i64 %t99, i64 %t100)
  store i64 %t101, ptr %pos.addr, align 8
  %t102 = load i64, ptr %pos.addr, align 8
  %t103 = load i64, ptr %len.addr, align 8
  %t104 = icmp slt i64 %t102, %t103
  store i1 %t104, ptr %and.val13, align 1
  br i1 %t104, label %and.rhs13, label %and.end13
and.rhs13:
  %t105 = load ptr, ptr %buf.addr, align 8
  %t106 = load i64, ptr %pos.addr, align 8
  %t107 = call i32 @char-at(ptr %t105, i64 %t106)
  %t108 = icmp eq i32 %t107, 41
  store i1 %t108, ptr %and.val13, align 1
  br label %and.end13
and.end13:
  %t109 = load i1, ptr %and.val13, align 1
  br i1 %t109, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t110 = load i64, ptr %pos.addr, align 8
  %t111 = sext i32 1 to i64
  %t112 = add nsw i64 %t110, %t111
  store i64 %t112, ptr %pos.addr, align 8
  br label %cond.end12
cond.end12:
  store i32 1, ptr %pdone.addr.50, align 4
  br label %cond.end8
cond.end8:
  %t113 = load i32, ptr %pdone.addr.50, align 4
  %t114 = icmp eq i32 %t113, 0
  br i1 %t114, label %cond.then14.0, label %cond.end14
cond.then14.0:
  %t116 = sext i32 0 to i64
  store i64 %t116, ptr %void-check-end.addr.115, align 8
  %t118 = load ptr, ptr %buf.addr, align 8
  %t119 = load i64, ptr %pos.addr, align 8
  %t120 = load i64, ptr %len.addr, align 8
  %t121 = call ptr @c-read-ident(ptr %t118, i64 %t119, i64 %t120, ptr %void-check-end.addr.115)
  store ptr %t121, ptr %void-check.addr.117, align 8
  %t122 = load ptr, ptr %void-check.addr.117, align 8
  %t123 = getelementptr inbounds [5 x i8], ptr @.str.437, i64 0, i64 0
  %t124 = call i32 @strcmp(ptr %t122, ptr %t123)
  %t125 = icmp eq i32 %t124, 0
  br i1 %t125, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t127 = load ptr, ptr %buf.addr, align 8
  %t128 = load i64, ptr %void-check-end.addr.115, align 8
  %t129 = load i64, ptr %len.addr, align 8
  %t130 = call i64 @c-skip-ws(ptr %t127, i64 %t128, i64 %t129)
  store i64 %t130, ptr %after-void.addr.126, align 8
  %t131 = load i64, ptr %after-void.addr.126, align 8
  %t132 = load i64, ptr %len.addr, align 8
  %t133 = icmp slt i64 %t131, %t132
  store i1 %t133, ptr %and.val17, align 1
  br i1 %t133, label %and.rhs17, label %and.end17
and.rhs17:
  %t134 = load ptr, ptr %buf.addr, align 8
  %t135 = load i64, ptr %after-void.addr.126, align 8
  %t136 = call i32 @char-at(ptr %t134, i64 %t135)
  %t137 = icmp eq i32 %t136, 41
  store i1 %t137, ptr %and.val17, align 1
  br label %and.end17
and.end17:
  %t138 = load i1, ptr %and.val17, align 1
  br i1 %t138, label %cond.then16.0, label %cond.end16
cond.then16.0:
  %t139 = load i64, ptr %after-void.addr.126, align 8
  %t140 = sext i32 1 to i64
  %t141 = add nsw i64 %t139, %t140
  store i64 %t141, ptr %pos.addr, align 8
  store i32 1, ptr %pdone.addr.50, align 4
  br label %cond.end16
cond.end16:
  br label %cond.end15
cond.end15:
  %t142 = load i32, ptr %pdone.addr.50, align 4
  %t143 = icmp eq i32 %t142, 0
  br i1 %t143, label %cond.then18.0, label %cond.end18
cond.then18.0:
  %t145 = sext i32 0 to i64
  store i64 %t145, ptr %ptype-end.addr.144, align 8
  %t147 = load ptr, ptr %buf.addr, align 8
  %t148 = load i64, ptr %pos.addr, align 8
  %t149 = load i64, ptr %len.addr, align 8
  %t150 = call ptr @c-parse-type(ptr %t147, i64 %t148, i64 %t149, ptr %ptype-end.addr.144)
  store ptr %t150, ptr %ptype.addr.146, align 8
  %t151 = load i64, ptr %ptype-end.addr.144, align 8
  store i64 %t151, ptr %pos.addr, align 8
  %t152 = load ptr, ptr %buf.addr, align 8
  %t153 = load i64, ptr %pos.addr, align 8
  %t154 = load i64, ptr %len.addr, align 8
  %t155 = call i64 @c-skip-ws(ptr %t152, i64 %t153, i64 %t154)
  store i64 %t155, ptr %pos.addr, align 8
  %t156 = load i64, ptr %pos.addr, align 8
  %t157 = load i64, ptr %len.addr, align 8
  %t158 = icmp slt i64 %t156, %t157
  store i1 %t158, ptr %and.val20, align 1
  br i1 %t158, label %and.rhs20, label %and.end20
and.rhs20:
  %t159 = load ptr, ptr %buf.addr, align 8
  %t160 = load i64, ptr %pos.addr, align 8
  %t161 = call i32 @char-at(ptr %t159, i64 %t160)
  %t162 = icmp eq i32 %t161, 40
  store i1 %t162, ptr %and.val20, align 1
  br label %and.end20
and.end20:
  %t163 = load i1, ptr %and.val20, align 1
  br i1 %t163, label %cond.then19.0, label %cond.end19
cond.then19.0:
  %t164 = load ptr, ptr %buf.addr, align 8
  %t165 = load i64, ptr %pos.addr, align 8
  %t166 = load i64, ptr %len.addr, align 8
  %t167 = call i64 @c-skip-parens(ptr %t164, i64 %t165, i64 %t166)
  store i64 %t167, ptr %pos.addr, align 8
  %t168 = load ptr, ptr %buf.addr, align 8
  %t169 = load i64, ptr %pos.addr, align 8
  %t170 = load i64, ptr %len.addr, align 8
  %t171 = call i64 @c-skip-ws(ptr %t168, i64 %t169, i64 %t170)
  store i64 %t171, ptr %pos.addr, align 8
  %t172 = load i64, ptr %pos.addr, align 8
  %t173 = load i64, ptr %len.addr, align 8
  %t174 = icmp slt i64 %t172, %t173
  store i1 %t174, ptr %and.val22, align 1
  br i1 %t174, label %and.rhs22, label %and.end22
and.rhs22:
  %t175 = load ptr, ptr %buf.addr, align 8
  %t176 = load i64, ptr %pos.addr, align 8
  %t177 = call i32 @char-at(ptr %t175, i64 %t176)
  %t178 = icmp eq i32 %t177, 40
  store i1 %t178, ptr %and.val22, align 1
  br label %and.end22
and.end22:
  %t179 = load i1, ptr %and.val22, align 1
  br i1 %t179, label %cond.then21.0, label %cond.end21
cond.then21.0:
  %t180 = load ptr, ptr %buf.addr, align 8
  %t181 = load i64, ptr %pos.addr, align 8
  %t182 = load i64, ptr %len.addr, align 8
  %t183 = call i64 @c-skip-parens(ptr %t180, i64 %t181, i64 %t182)
  store i64 %t183, ptr %pos.addr, align 8
  br label %cond.end21
cond.end21:
  %t184 = load ptr, ptr @ty-ptr, align 8
  store ptr %t184, ptr %ptype.addr.146, align 8
  br label %cond.end19
cond.end19:
  %t185 = load i64, ptr %pos.addr, align 8
  %t186 = load i64, ptr %len.addr, align 8
  %t187 = icmp slt i64 %t185, %t186
  store i1 %t187, ptr %and.val24, align 1
  br i1 %t187, label %and.rhs24, label %and.end24
and.rhs24:
  %t188 = load ptr, ptr %buf.addr, align 8
  %t189 = load i64, ptr %pos.addr, align 8
  %t190 = call i32 @char-at(ptr %t188, i64 %t189)
  %t191 = icmp sge i32 %t190, 65
  store i1 %t191, ptr %and.val26, align 1
  br i1 %t191, label %and.rhs26, label %and.end26
and.rhs26:
  %t192 = load ptr, ptr %buf.addr, align 8
  %t193 = load i64, ptr %pos.addr, align 8
  %t194 = call i32 @char-at(ptr %t192, i64 %t193)
  %t195 = icmp sle i32 %t194, 90
  store i1 %t195, ptr %and.val26, align 1
  br label %and.end26
and.end26:
  %t196 = load i1, ptr %and.val26, align 1
  store i1 %t196, ptr %or.val25, align 1
  br i1 %t196, label %or.end25, label %or.rhs25
or.rhs25:
  %t197 = load ptr, ptr %buf.addr, align 8
  %t198 = load i64, ptr %pos.addr, align 8
  %t199 = call i32 @char-at(ptr %t197, i64 %t198)
  %t200 = icmp sge i32 %t199, 97
  store i1 %t200, ptr %and.val28, align 1
  br i1 %t200, label %and.rhs28, label %and.end28
and.rhs28:
  %t201 = load ptr, ptr %buf.addr, align 8
  %t202 = load i64, ptr %pos.addr, align 8
  %t203 = call i32 @char-at(ptr %t201, i64 %t202)
  %t204 = icmp sle i32 %t203, 122
  store i1 %t204, ptr %and.val28, align 1
  br label %and.end28
and.end28:
  %t205 = load i1, ptr %and.val28, align 1
  store i1 %t205, ptr %or.val27, align 1
  br i1 %t205, label %or.end27, label %or.rhs27
or.rhs27:
  %t206 = load ptr, ptr %buf.addr, align 8
  %t207 = load i64, ptr %pos.addr, align 8
  %t208 = call i32 @char-at(ptr %t206, i64 %t207)
  %t209 = icmp eq i32 %t208, 95
  store i1 %t209, ptr %or.val27, align 1
  br label %or.end27
or.end27:
  %t210 = load i1, ptr %or.val27, align 1
  store i1 %t210, ptr %or.val25, align 1
  br label %or.end25
or.end25:
  %t211 = load i1, ptr %or.val25, align 1
  store i1 %t211, ptr %and.val24, align 1
  br label %and.end24
and.end24:
  %t212 = load i1, ptr %and.val24, align 1
  br i1 %t212, label %cond.then23.0, label %cond.end23
cond.then23.0:
  %t214 = sext i32 0 to i64
  store i64 %t214, ptr %skip-end.addr.213, align 8
  %t216 = load ptr, ptr %buf.addr, align 8
  %t217 = load i64, ptr %pos.addr, align 8
  %t218 = load i64, ptr %len.addr, align 8
  %t219 = call ptr @c-read-ident(ptr %t216, i64 %t217, i64 %t218, ptr %skip-end.addr.213)
  store ptr %t219, ptr %skip.addr.215, align 8
  %t220 = load i64, ptr %skip-end.addr.213, align 8
  store i64 %t220, ptr %pos.addr, align 8
  br label %cond.end23
cond.end23:
  %t221 = load ptr, ptr %buf.addr, align 8
  %t222 = load i64, ptr %pos.addr, align 8
  %t223 = load i64, ptr %len.addr, align 8
  %t224 = call i64 @c-skip-ws(ptr %t221, i64 %t222, i64 %t223)
  store i64 %t224, ptr %pos.addr, align 8
  br label %while.cond29
while.cond29:
  %t225 = load i64, ptr %pos.addr, align 8
  %t226 = load i64, ptr %len.addr, align 8
  %t227 = icmp slt i64 %t225, %t226
  store i1 %t227, ptr %and.val30, align 1
  br i1 %t227, label %and.rhs30, label %and.end30
and.rhs30:
  %t228 = load ptr, ptr %buf.addr, align 8
  %t229 = load i64, ptr %pos.addr, align 8
  %t230 = call i32 @char-at(ptr %t228, i64 %t229)
  %t231 = icmp eq i32 %t230, 91
  store i1 %t231, ptr %and.val30, align 1
  br label %and.end30
and.end30:
  %t232 = load i1, ptr %and.val30, align 1
  br i1 %t232, label %while.body29, label %while.end29
while.body29:
  br label %while.cond31
while.cond31:
  %t233 = load i64, ptr %pos.addr, align 8
  %t234 = load i64, ptr %len.addr, align 8
  %t235 = icmp slt i64 %t233, %t234
  store i1 %t235, ptr %and.val32, align 1
  br i1 %t235, label %and.rhs32, label %and.end32
and.rhs32:
  %t236 = load ptr, ptr %buf.addr, align 8
  %t237 = load i64, ptr %pos.addr, align 8
  %t238 = call i32 @char-at(ptr %t236, i64 %t237)
  %t239 = icmp ne i32 %t238, 93
  store i1 %t239, ptr %and.val32, align 1
  br label %and.end32
and.end32:
  %t240 = load i1, ptr %and.val32, align 1
  br i1 %t240, label %while.body31, label %while.end31
while.body31:
  %t241 = load i64, ptr %pos.addr, align 8
  %t242 = sext i32 1 to i64
  %t243 = add nsw i64 %t241, %t242
  store i64 %t243, ptr %pos.addr, align 8
  br label %while.cond31
while.end31:
  %t244 = load i64, ptr %pos.addr, align 8
  %t245 = load i64, ptr %len.addr, align 8
  %t246 = icmp slt i64 %t244, %t245
  br i1 %t246, label %cond.then33.0, label %cond.end33
cond.then33.0:
  %t247 = load i64, ptr %pos.addr, align 8
  %t248 = sext i32 1 to i64
  %t249 = add nsw i64 %t247, %t248
  store i64 %t249, ptr %pos.addr, align 8
  br label %cond.end33
cond.end33:
  %t250 = load ptr, ptr %buf.addr, align 8
  %t251 = load i64, ptr %pos.addr, align 8
  %t252 = load i64, ptr %len.addr, align 8
  %t253 = call i64 @c-skip-ws(ptr %t250, i64 %t251, i64 %t252)
  store i64 %t253, ptr %pos.addr, align 8
  %t254 = load ptr, ptr @ty-ptr, align 8
  store ptr %t254, ptr %ptype.addr.146, align 8
  br label %while.cond29
while.end29:
  %t255 = load i32, ptr %num-params.addr.48, align 4
  %t256 = icmp slt i32 %t255, 16
  br i1 %t256, label %cond.then34.0, label %cond.end34
cond.then34.0:
  %t257 = load ptr, ptr %param-types.addr.43, align 8
  %t258 = load i32, ptr %num-params.addr.48, align 4
  %t259 = sext i32 %t258 to i64
  %t260 = load ptr, ptr %ptype.addr.146, align 8
  %t261 = getelementptr inbounds ptr, ptr %t257, i64 %t259
  store ptr %t260, ptr %t261, align 8
  br label %cond.end34
cond.end34:
  %t262 = load i32, ptr %num-params.addr.48, align 4
  %t263 = add nsw i32 %t262, 1
  store i32 %t263, ptr %num-params.addr.48, align 4
  %t264 = load ptr, ptr %buf.addr, align 8
  %t265 = load i64, ptr %pos.addr, align 8
  %t266 = load i64, ptr %len.addr, align 8
  %t267 = call i64 @c-skip-ws(ptr %t264, i64 %t265, i64 %t266)
  store i64 %t267, ptr %pos.addr, align 8
  %t268 = load i64, ptr %pos.addr, align 8
  %t269 = load i64, ptr %len.addr, align 8
  %t270 = icmp slt i64 %t268, %t269
  store i1 %t270, ptr %and.val36, align 1
  br i1 %t270, label %and.rhs36, label %and.end36
and.rhs36:
  %t271 = load ptr, ptr %buf.addr, align 8
  %t272 = load i64, ptr %pos.addr, align 8
  %t273 = call i32 @char-at(ptr %t271, i64 %t272)
  %t274 = icmp eq i32 %t273, 44
  store i1 %t274, ptr %and.val36, align 1
  br label %and.end36
and.end36:
  %t275 = load i1, ptr %and.val36, align 1
  br i1 %t275, label %cond.then35.0, label %cond.end35
cond.then35.0:
  %t276 = load i64, ptr %pos.addr, align 8
  %t277 = sext i32 1 to i64
  %t278 = add nsw i64 %t276, %t277
  store i64 %t278, ptr %pos.addr, align 8
  br label %cond.end35
cond.end35:
  br label %cond.end18
cond.end18:
  br label %cond.end14
cond.end14:
  br label %cond.end7
cond.end7:
  br label %cond.end5
cond.end5:
  br label %while.cond3
while.end3:
  %t279 = load ptr, ptr %buf.addr, align 8
  %t280 = load i64, ptr %pos.addr, align 8
  %t281 = load i64, ptr %len.addr, align 8
  %t282 = call i64 @c-skip-ws(ptr %t279, i64 %t280, i64 %t281)
  store i64 %t282, ptr %pos.addr, align 8
  store i32 1, ptr %attr-check.addr.283, align 4
  br label %while.cond37
while.cond37:
  %t284 = load i32, ptr %attr-check.addr.283, align 4
  %t285 = icmp ne i32 %t284, 0
  br i1 %t285, label %while.body37, label %while.end37
while.body37:
  store i32 0, ptr %attr-check.addr.283, align 4
  %t287 = sext i32 0 to i64
  store i64 %t287, ptr %ae.addr.286, align 8
  %t289 = load ptr, ptr %buf.addr, align 8
  %t290 = load i64, ptr %pos.addr, align 8
  %t291 = load i64, ptr %len.addr, align 8
  %t292 = call ptr @c-read-ident(ptr %t289, i64 %t290, i64 %t291, ptr %ae.addr.286)
  store ptr %t292, ptr %at.addr.288, align 8
  %t293 = load ptr, ptr %at.addr.288, align 8
  %t294 = getelementptr inbounds [14 x i8], ptr @.str.438, i64 0, i64 0
  %t295 = call i32 @strcmp(ptr %t293, ptr %t294)
  %t296 = icmp eq i32 %t295, 0
  br i1 %t296, label %cond.then38.0, label %cond.end38
cond.then38.0:
  %t297 = load ptr, ptr %buf.addr, align 8
  %t298 = load i64, ptr %ae.addr.286, align 8
  %t299 = load i64, ptr %len.addr, align 8
  %t300 = call i64 @c-skip-ws(ptr %t297, i64 %t298, i64 %t299)
  store i64 %t300, ptr %pos.addr, align 8
  %t301 = load i64, ptr %pos.addr, align 8
  %t302 = load i64, ptr %len.addr, align 8
  %t303 = icmp slt i64 %t301, %t302
  store i1 %t303, ptr %and.val40, align 1
  br i1 %t303, label %and.rhs40, label %and.end40
and.rhs40:
  %t304 = load ptr, ptr %buf.addr, align 8
  %t305 = load i64, ptr %pos.addr, align 8
  %t306 = call i32 @char-at(ptr %t304, i64 %t305)
  %t307 = icmp eq i32 %t306, 40
  store i1 %t307, ptr %and.val40, align 1
  br label %and.end40
and.end40:
  %t308 = load i1, ptr %and.val40, align 1
  br i1 %t308, label %cond.then39.0, label %cond.end39
cond.then39.0:
  %t309 = load ptr, ptr %buf.addr, align 8
  %t310 = load i64, ptr %pos.addr, align 8
  %t311 = load i64, ptr %len.addr, align 8
  %t312 = call i64 @c-skip-parens(ptr %t309, i64 %t310, i64 %t311)
  store i64 %t312, ptr %pos.addr, align 8
  br label %cond.end39
cond.end39:
  %t313 = load ptr, ptr %buf.addr, align 8
  %t314 = load i64, ptr %pos.addr, align 8
  %t315 = load i64, ptr %len.addr, align 8
  %t316 = call i64 @c-skip-ws(ptr %t313, i64 %t314, i64 %t315)
  store i64 %t316, ptr %pos.addr, align 8
  store i32 1, ptr %attr-check.addr.283, align 4
  br label %cond.end38
cond.end38:
  %t317 = load ptr, ptr %at.addr.288, align 8
  %t318 = getelementptr inbounds [8 x i8], ptr @.str.439, i64 0, i64 0
  %t319 = call i32 @strcmp(ptr %t317, ptr %t318)
  %t320 = icmp eq i32 %t319, 0
  br i1 %t320, label %cond.then41.0, label %cond.end41
cond.then41.0:
  %t321 = load ptr, ptr %buf.addr, align 8
  %t322 = load i64, ptr %ae.addr.286, align 8
  %t323 = load i64, ptr %len.addr, align 8
  %t324 = call i64 @c-skip-ws(ptr %t321, i64 %t322, i64 %t323)
  store i64 %t324, ptr %pos.addr, align 8
  %t325 = load i64, ptr %pos.addr, align 8
  %t326 = load i64, ptr %len.addr, align 8
  %t327 = icmp slt i64 %t325, %t326
  store i1 %t327, ptr %and.val43, align 1
  br i1 %t327, label %and.rhs43, label %and.end43
and.rhs43:
  %t328 = load ptr, ptr %buf.addr, align 8
  %t329 = load i64, ptr %pos.addr, align 8
  %t330 = call i32 @char-at(ptr %t328, i64 %t329)
  %t331 = icmp eq i32 %t330, 40
  store i1 %t331, ptr %and.val43, align 1
  br label %and.end43
and.end43:
  %t332 = load i1, ptr %and.val43, align 1
  br i1 %t332, label %cond.then42.0, label %cond.end42
cond.then42.0:
  %t333 = load ptr, ptr %buf.addr, align 8
  %t334 = load i64, ptr %pos.addr, align 8
  %t335 = load i64, ptr %len.addr, align 8
  %t336 = call i64 @c-skip-parens(ptr %t333, i64 %t334, i64 %t335)
  store i64 %t336, ptr %pos.addr, align 8
  br label %cond.end42
cond.end42:
  %t337 = load ptr, ptr %buf.addr, align 8
  %t338 = load i64, ptr %pos.addr, align 8
  %t339 = load i64, ptr %len.addr, align 8
  %t340 = call i64 @c-skip-ws(ptr %t337, i64 %t338, i64 %t339)
  store i64 %t340, ptr %pos.addr, align 8
  store i32 1, ptr %attr-check.addr.283, align 4
  br label %cond.end41
cond.end41:
  br label %while.cond37
while.end37:
  %t341 = load i64, ptr %pos.addr, align 8
  %t342 = load i64, ptr %len.addr, align 8
  %t343 = icmp slt i64 %t341, %t342
  store i1 %t343, ptr %and.val45, align 1
  br i1 %t343, label %and.rhs45, label %and.end45
and.rhs45:
  %t344 = load ptr, ptr %buf.addr, align 8
  %t345 = load i64, ptr %pos.addr, align 8
  %t346 = call i32 @char-at(ptr %t344, i64 %t345)
  %t347 = icmp eq i32 %t346, 59
  store i1 %t347, ptr %and.val45, align 1
  br label %and.end45
and.end45:
  %t348 = load i1, ptr %and.val45, align 1
  br i1 %t348, label %cond.then44.0, label %cond.end44
cond.then44.0:
  %t349 = load i64, ptr %pos.addr, align 8
  %t350 = sext i32 1 to i64
  %t351 = add nsw i64 %t349, %t350
  store i64 %t351, ptr %pos.addr, align 8
  br label %cond.end44
cond.end44:
  %t352 = load ptr, ptr %out-end.addr, align 8
  %t353 = load i64, ptr %pos.addr, align 8
  store i64 %t353, ptr %t352, align 8
  %t355 = call ptr @make-type(i32 11)
  store ptr %t355, ptr %ft.addr.354, align 8
  %t356 = load ptr, ptr %ft.addr.354, align 8
  %t357 = load ptr, ptr %ret-type.addr.2, align 8
  %t358 = getelementptr inbounds %Type, ptr %t356, i32 0, i32 1
  store ptr %t357, ptr %t358, align 8
  %t359 = load ptr, ptr %ft.addr.354, align 8
  %t360 = load i32, ptr %num-params.addr.48, align 4
  %t361 = getelementptr inbounds %Type, ptr %t359, i32 0, i32 3
  store i32 %t360, ptr %t361, align 4
  %t362 = load ptr, ptr %ft.addr.354, align 8
  %t363 = load i32, ptr %num-params.addr.48, align 4
  %t364 = call i64 @i64(i32 %t363)
  %t365 = call i64 @i64(i32 8)
  %t366 = mul nsw i64 %t364, %t365
  %t367 = call ptr @arena-alloc(i64 %t366)
  %t368 = getelementptr inbounds %Type, ptr %t362, i32 0, i32 2
  store ptr %t367, ptr %t368, align 8
  store i32 0, ptr %j.addr.369, align 4
  br label %while.cond46
while.cond46:
  %t370 = load i32, ptr %j.addr.369, align 4
  %t371 = load i32, ptr %num-params.addr.48, align 4
  %t372 = icmp slt i32 %t370, %t371
  br i1 %t372, label %while.body46, label %while.end46
while.body46:
  %t373 = load ptr, ptr %ft.addr.354, align 8
  %t374 = getelementptr inbounds %Type, ptr %t373, i32 0, i32 2
  %t375 = load ptr, ptr %t374, align 8
  %t376 = load i32, ptr %j.addr.369, align 4
  %t377 = sext i32 %t376 to i64
  %t378 = load ptr, ptr %param-types.addr.43, align 8
  %t379 = load i32, ptr %j.addr.369, align 4
  %t380 = sext i32 %t379 to i64
  %t381 = getelementptr inbounds ptr, ptr %t378, i64 %t380
  %t382 = load ptr, ptr %t381, align 8
  %t383 = getelementptr inbounds ptr, ptr %t375, i64 %t377
  store ptr %t382, ptr %t383, align 8
  %t384 = load i32, ptr %j.addr.369, align 4
  %t385 = add nsw i32 %t384, 1
  store i32 %t385, ptr %j.addr.369, align 4
  br label %while.cond46
while.end46:
  %t386 = load ptr, ptr %ft.addr.354, align 8
  %t387 = load i32, ptr %is-variadic.addr.49, align 4
  %t388 = getelementptr inbounds %Type, ptr %t386, i32 0, i32 4
  store i32 %t387, ptr %t388, align 4
  %t389 = load ptr, ptr @g-globals, align 8
  %t390 = load ptr, ptr %fname.addr.14, align 8
  %t391 = call ptr @scope-lookup(ptr %t389, ptr %t390)
  %t392 = icmp eq ptr %t391, null
  br i1 %t392, label %cond.then47.0, label %cond.end47
cond.then47.0:
  %t393 = load ptr, ptr @g-globals, align 8
  %t394 = load ptr, ptr %fname.addr.14, align 8
  %t395 = load ptr, ptr %ft.addr.354, align 8
  %t396 = getelementptr inbounds [4 x i8], ptr @.str.440, i64 0, i64 0
  %t397 = load ptr, ptr %fname.addr.14, align 8
  %t398 = call ptr @fmt-s(ptr %t396, ptr %t397)
  %t399 = call ptr @scope-define(ptr %t393, ptr %t394, ptr %t395, ptr %t398, i32 0)
  %t400 = load ptr, ptr %fname.addr.14, align 8
  %t401 = getelementptr inbounds [7 x i8], ptr @.str.441, i64 0, i64 0
  %t402 = call i32 @strcmp(ptr %t400, ptr %t401)
  %t403 = icmp eq i32 %t402, 0
  br i1 %t403, label %cond.then48.0, label %cond.end48
cond.then48.0:
  store i32 1, ptr @g-malloc-decl-done, align 4
  br label %cond.end48
cond.end48:
  %t404 = load ptr, ptr @g-out, align 8
  %t405 = getelementptr inbounds [16 x i8], ptr @.str.442, i64 0, i64 0
  %t406 = load ptr, ptr %ret-type.addr.2, align 8
  %t407 = call ptr @type-to-ir(ptr %t406)
  %t408 = load ptr, ptr %fname.addr.14, align 8
  %t409 = call i32 (ptr, ptr, ...) @fprintf(ptr %t404, ptr %t405, ptr %t407, ptr %t408)
  store i32 0, ptr %j.addr.410, align 4
  br label %while.cond49
while.cond49:
  %t411 = load i32, ptr %j.addr.410, align 4
  %t412 = load i32, ptr %num-params.addr.48, align 4
  %t413 = icmp slt i32 %t411, %t412
  br i1 %t413, label %while.body49, label %while.end49
while.body49:
  %t414 = load i32, ptr %j.addr.410, align 4
  %t415 = icmp ne i32 %t414, 0
  br i1 %t415, label %cond.then50.0, label %cond.end50
cond.then50.0:
  %t416 = load ptr, ptr @g-out, align 8
  %t417 = getelementptr inbounds [3 x i8], ptr @.str.443, i64 0, i64 0
  %t418 = call i32 (ptr, ptr, ...) @fprintf(ptr %t416, ptr %t417)
  br label %cond.end50
cond.end50:
  %t419 = load ptr, ptr @g-out, align 8
  %t420 = getelementptr inbounds [3 x i8], ptr @.str.444, i64 0, i64 0
  %t421 = load ptr, ptr %ft.addr.354, align 8
  %t422 = getelementptr inbounds %Type, ptr %t421, i32 0, i32 2
  %t423 = load ptr, ptr %t422, align 8
  %t424 = load i32, ptr %j.addr.410, align 4
  %t425 = sext i32 %t424 to i64
  %t426 = getelementptr inbounds ptr, ptr %t423, i64 %t425
  %t427 = load ptr, ptr %t426, align 8
  %t428 = call ptr @type-to-ir(ptr %t427)
  %t429 = call i32 (ptr, ptr, ...) @fprintf(ptr %t419, ptr %t420, ptr %t428)
  %t430 = load i32, ptr %j.addr.410, align 4
  %t431 = add nsw i32 %t430, 1
  store i32 %t431, ptr %j.addr.410, align 4
  br label %while.cond49
while.end49:
  %t432 = load i32, ptr %is-variadic.addr.49, align 4
  %t433 = icmp ne i32 %t432, 0
  br i1 %t433, label %cond.then51.0, label %cond.end51
cond.then51.0:
  %t435 = getelementptr inbounds [1 x i8], ptr @.str.445, i64 0, i64 0
  store ptr %t435, ptr %sep.addr.434, align 8
  %t436 = load i32, ptr %num-params.addr.48, align 4
  %t437 = icmp ne i32 %t436, 0
  br i1 %t437, label %cond.then52.0, label %cond.end52
cond.then52.0:
  %t438 = getelementptr inbounds [3 x i8], ptr @.str.446, i64 0, i64 0
  store ptr %t438, ptr %sep.addr.434, align 8
  br label %cond.end52
cond.end52:
  %t439 = load ptr, ptr @g-out, align 8
  %t440 = getelementptr inbounds [6 x i8], ptr @.str.447, i64 0, i64 0
  %t441 = load ptr, ptr %sep.addr.434, align 8
  %t442 = call i32 (ptr, ptr, ...) @fprintf(ptr %t439, ptr %t440, ptr %t441)
  br label %cond.end51
cond.end51:
  %t443 = load ptr, ptr @g-out, align 8
  %t444 = getelementptr inbounds [3 x i8], ptr @.str.448, i64 0, i64 0
  %t445 = call i32 (ptr, ptr, ...) @fprintf(ptr %t443, ptr %t444)
  br label %cond.end47
cond.end47:
  ret i32 1
}

define ptr @read-pipe-output(ptr %cmd.arg, ptr %out-len.arg) {
entry:
  %cmd.addr = alloca ptr, align 8
  store ptr %cmd.arg, ptr %cmd.addr, align 8
  %out-len.addr = alloca ptr, align 8
  store ptr %out-len.arg, ptr %out-len.addr, align 8
  %fp.addr.0 = alloca ptr, align 8
  %bufsz.addr.8 = alloca i64, align 8
  %buf.addr.10 = alloca ptr, align 8
  %total.addr.13 = alloca i64, align 8
  %chunk.addr.15 = alloca i64, align 8
  %t1 = load ptr, ptr %cmd.addr, align 8
  %t2 = getelementptr inbounds [2 x i8], ptr @.str.449, i64 0, i64 0
  %t3 = call ptr @popen(ptr %t1, ptr %t2)
  store ptr %t3, ptr %fp.addr.0, align 8
  %t4 = load ptr, ptr %fp.addr.0, align 8
  %t5 = icmp eq ptr %t4, null
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t6 = load ptr, ptr %out-len.addr, align 8
  %t7 = sext i32 0 to i64
  store i64 %t7, ptr %t6, align 8
  ret ptr null
cond.end0:
  %t9 = sext i32 65536 to i64
  store i64 %t9, ptr %bufsz.addr.8, align 8
  %t11 = load i64, ptr %bufsz.addr.8, align 8
  %t12 = call ptr @malloc(i64 %t11)
  store ptr %t12, ptr %buf.addr.10, align 8
  %t14 = sext i32 0 to i64
  store i64 %t14, ptr %total.addr.13, align 8
  %t16 = load ptr, ptr %buf.addr.10, align 8
  %t17 = load i64, ptr %total.addr.13, align 8
  %t18 = getelementptr inbounds i8, ptr %t16, i64 %t17
  %t19 = sext i32 1 to i64
  %t20 = load i64, ptr %bufsz.addr.8, align 8
  %t21 = load i64, ptr %total.addr.13, align 8
  %t22 = sub nsw i64 %t20, %t21
  %t23 = sext i32 1 to i64
  %t24 = sub nsw i64 %t22, %t23
  %t25 = load ptr, ptr %fp.addr.0, align 8
  %t26 = call i64 @fread(ptr %t18, i64 %t19, i64 %t24, ptr %t25)
  store i64 %t26, ptr %chunk.addr.15, align 8
  %t27 = load i64, ptr %total.addr.13, align 8
  %t28 = load i64, ptr %chunk.addr.15, align 8
  %t29 = add nsw i64 %t27, %t28
  store i64 %t29, ptr %total.addr.13, align 8
  br label %while.cond1
while.cond1:
  %t30 = load i64, ptr %chunk.addr.15, align 8
  %t31 = sext i32 0 to i64
  %t32 = icmp sgt i64 %t30, %t31
  br i1 %t32, label %while.body1, label %while.end1
while.body1:
  %t33 = load i64, ptr %total.addr.13, align 8
  %t34 = sext i32 1 to i64
  %t35 = add nsw i64 %t33, %t34
  %t36 = load i64, ptr %bufsz.addr.8, align 8
  %t37 = icmp sge i64 %t35, %t36
  br i1 %t37, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t38 = load i64, ptr %bufsz.addr.8, align 8
  %t39 = sext i32 2 to i64
  %t40 = mul nsw i64 %t38, %t39
  store i64 %t40, ptr %bufsz.addr.8, align 8
  %t41 = load ptr, ptr %buf.addr.10, align 8
  %t42 = load i64, ptr %bufsz.addr.8, align 8
  %t43 = call ptr @realloc(ptr %t41, i64 %t42)
  store ptr %t43, ptr %buf.addr.10, align 8
  br label %cond.end2
cond.end2:
  %t44 = load ptr, ptr %buf.addr.10, align 8
  %t45 = load i64, ptr %total.addr.13, align 8
  %t46 = getelementptr inbounds i8, ptr %t44, i64 %t45
  %t47 = sext i32 1 to i64
  %t48 = load i64, ptr %bufsz.addr.8, align 8
  %t49 = load i64, ptr %total.addr.13, align 8
  %t50 = sub nsw i64 %t48, %t49
  %t51 = sext i32 1 to i64
  %t52 = sub nsw i64 %t50, %t51
  %t53 = load ptr, ptr %fp.addr.0, align 8
  %t54 = call i64 @fread(ptr %t46, i64 %t47, i64 %t52, ptr %t53)
  store i64 %t54, ptr %chunk.addr.15, align 8
  %t55 = load i64, ptr %total.addr.13, align 8
  %t56 = load i64, ptr %chunk.addr.15, align 8
  %t57 = add nsw i64 %t55, %t56
  store i64 %t57, ptr %total.addr.13, align 8
  br label %while.cond1
while.end1:
  %t58 = load ptr, ptr %buf.addr.10, align 8
  %t59 = load i64, ptr %total.addr.13, align 8
  %t60 = getelementptr inbounds i8, ptr %t58, i64 %t59
  %t61 = trunc i32 0 to i8
  store i8 %t61, ptr %t60, align 1
  %t62 = load ptr, ptr %fp.addr.0, align 8
  %t63 = call i32 @pclose(ptr %t62)
  %t64 = load ptr, ptr %out-len.addr, align 8
  %t65 = load i64, ptr %total.addr.13, align 8
  store i64 %t65, ptr %t64, align 8
  %t66 = load ptr, ptr %buf.addr.10, align 8
  ret ptr %t66
}

define void @emit-c-include(ptr %header-path.arg, i32 %line.arg) {
entry:
  %header-path.addr = alloca ptr, align 8
  store ptr %header-path.arg, ptr %header-path.addr, align 8
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %cmd.addr.0 = alloca ptr, align 8
  %buf-len.addr.7 = alloca i64, align 8
  %buf.addr.9 = alloca ptr, align 8
  %pos.addr.18 = alloca i64, align 8
  %prev-pos.addr.20 = alloca i64, align 8
  %and.val5 = alloca i1, align 1
  %tok-end.addr.54 = alloca i64, align 8
  %tok.addr.56 = alloca ptr, align 8
  %decl-end.addr.65 = alloca i64, align 8
  %ok.addr.67 = alloca i32, align 4
  %and.val10 = alloca i1, align 1
  %and.val13 = alloca i1, align 1
  %and.val14 = alloca i1, align 1
  %brace-depth.addr.110 = alloca i32, align 4
  %and.val17 = alloca i1, align 1
  %and.val21 = alloca i1, align 1
  %and.val22 = alloca i1, align 1
  %and.val23 = alloca i1, align 1
  %t1 = alloca i8, i32 512, align 1
  store ptr %t1, ptr %cmd.addr.0, align 8
  %t2 = load ptr, ptr %cmd.addr.0, align 8
  %t3 = sext i32 512 to i64
  %t4 = getelementptr inbounds [48 x i8], ptr @.str.450, i64 0, i64 0
  %t5 = load ptr, ptr %header-path.addr, align 8
  %t6 = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %t2, i64 %t3, ptr %t4, ptr %t5)
  %t8 = sext i32 0 to i64
  store i64 %t8, ptr %buf-len.addr.7, align 8
  %t10 = load ptr, ptr %cmd.addr.0, align 8
  %t11 = call ptr @read-pipe-output(ptr %t10, ptr %buf-len.addr.7)
  store ptr %t11, ptr %buf.addr.9, align 8
  %t12 = load ptr, ptr %buf.addr.9, align 8
  %t13 = icmp eq ptr %t12, null
  br i1 %t13, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t14 = load i32, ptr %line.addr, align 4
  %t15 = getelementptr inbounds [37 x i8], ptr @.str.451, i64 0, i64 0
  %t16 = load ptr, ptr %header-path.addr, align 8
  %t17 = call ptr @fmt-s(ptr %t15, ptr %t16)
  call void @die-at(i32 %t14, ptr %t17)
  br label %cond.end0
cond.end0:
  %t19 = sext i32 0 to i64
  store i64 %t19, ptr %pos.addr.18, align 8
  %t21 = sext i32 -1 to i64
  store i64 %t21, ptr %prev-pos.addr.20, align 8
  br label %while.cond1
while.cond1:
  %t22 = load i64, ptr %pos.addr.18, align 8
  %t23 = load i64, ptr %buf-len.addr.7, align 8
  %t24 = icmp slt i64 %t22, %t23
  br i1 %t24, label %while.body1, label %while.end1
while.body1:
  %t25 = load i64, ptr %pos.addr.18, align 8
  store i64 %t25, ptr %prev-pos.addr.20, align 8
  %t26 = load ptr, ptr %buf.addr.9, align 8
  %t27 = load i64, ptr %pos.addr.18, align 8
  %t28 = load i64, ptr %buf-len.addr.7, align 8
  %t29 = call i64 @c-skip-ws(ptr %t26, i64 %t27, i64 %t28)
  store i64 %t29, ptr %pos.addr.18, align 8
  %t30 = load i64, ptr %pos.addr.18, align 8
  %t31 = load i64, ptr %buf-len.addr.7, align 8
  %t32 = icmp slt i64 %t30, %t31
  br i1 %t32, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t33 = load ptr, ptr %buf.addr.9, align 8
  %t34 = load i64, ptr %pos.addr.18, align 8
  %t35 = call i32 @char-at(ptr %t33, i64 %t34)
  %t36 = icmp eq i32 %t35, 35
  br i1 %t36, label %cond.then3.0, label %cond.test3.1
cond.then3.0:
  br label %while.cond4
while.cond4:
  %t37 = load i64, ptr %pos.addr.18, align 8
  %t38 = load i64, ptr %buf-len.addr.7, align 8
  %t39 = icmp slt i64 %t37, %t38
  store i1 %t39, ptr %and.val5, align 1
  br i1 %t39, label %and.rhs5, label %and.end5
and.rhs5:
  %t40 = load ptr, ptr %buf.addr.9, align 8
  %t41 = load i64, ptr %pos.addr.18, align 8
  %t42 = call i32 @char-at(ptr %t40, i64 %t41)
  %t43 = icmp ne i32 %t42, 10
  store i1 %t43, ptr %and.val5, align 1
  br label %and.end5
and.end5:
  %t44 = load i1, ptr %and.val5, align 1
  br i1 %t44, label %while.body4, label %while.end4
while.body4:
  %t45 = load i64, ptr %pos.addr.18, align 8
  %t46 = sext i32 1 to i64
  %t47 = add nsw i64 %t45, %t46
  store i64 %t47, ptr %pos.addr.18, align 8
  br label %while.cond4
while.end4:
  %t48 = load i64, ptr %pos.addr.18, align 8
  %t49 = load i64, ptr %buf-len.addr.7, align 8
  %t50 = icmp slt i64 %t48, %t49
  br i1 %t50, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t51 = load i64, ptr %pos.addr.18, align 8
  %t52 = sext i32 1 to i64
  %t53 = add nsw i64 %t51, %t52
  store i64 %t53, ptr %pos.addr.18, align 8
  br label %cond.end6
cond.end6:
  br label %cond.end3
cond.test3.1:
  br i1 1, label %cond.then3.1, label %cond.end3
cond.then3.1:
  %t55 = sext i32 0 to i64
  store i64 %t55, ptr %tok-end.addr.54, align 8
  %t57 = load ptr, ptr %buf.addr.9, align 8
  %t58 = load i64, ptr %pos.addr.18, align 8
  %t59 = load i64, ptr %buf-len.addr.7, align 8
  %t60 = call ptr @c-read-ident(ptr %t57, i64 %t58, i64 %t59, ptr %tok-end.addr.54)
  store ptr %t60, ptr %tok.addr.56, align 8
  %t61 = load ptr, ptr %tok.addr.56, align 8
  %t62 = getelementptr inbounds [7 x i8], ptr @.str.452, i64 0, i64 0
  %t63 = call i32 @strcmp(ptr %t61, ptr %t62)
  %t64 = icmp eq i32 %t63, 0
  br i1 %t64, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t66 = sext i32 0 to i64
  store i64 %t66, ptr %decl-end.addr.65, align 8
  %t68 = load ptr, ptr %buf.addr.9, align 8
  %t69 = load i64, ptr %pos.addr.18, align 8
  %t70 = load i64, ptr %buf-len.addr.7, align 8
  %t71 = load i32, ptr %line.addr, align 4
  %t72 = call i32 @c-parse-func-decl(ptr %t68, i64 %t69, i64 %t70, ptr %decl-end.addr.65, i32 %t71)
  store i32 %t72, ptr %ok.addr.67, align 4
  %t73 = load i32, ptr %ok.addr.67, align 4
  %t74 = icmp ne i32 %t73, 0
  br i1 %t74, label %cond.then8.0, label %cond.test8.1
cond.then8.0:
  %t75 = load i64, ptr %decl-end.addr.65, align 8
  store i64 %t75, ptr %pos.addr.18, align 8
  br label %cond.end8
cond.test8.1:
  br i1 1, label %cond.then8.1, label %cond.end8
cond.then8.1:
  br label %while.cond9
while.cond9:
  %t76 = load i64, ptr %pos.addr.18, align 8
  %t77 = load i64, ptr %buf-len.addr.7, align 8
  %t78 = icmp slt i64 %t76, %t77
  store i1 %t78, ptr %and.val10, align 1
  br i1 %t78, label %and.rhs10, label %and.end10
and.rhs10:
  %t79 = load ptr, ptr %buf.addr.9, align 8
  %t80 = load i64, ptr %pos.addr.18, align 8
  %t81 = call i32 @char-at(ptr %t79, i64 %t80)
  %t82 = icmp ne i32 %t81, 59
  store i1 %t82, ptr %and.val10, align 1
  br label %and.end10
and.end10:
  %t83 = load i1, ptr %and.val10, align 1
  br i1 %t83, label %while.body9, label %while.end9
while.body9:
  %t84 = load i64, ptr %pos.addr.18, align 8
  %t85 = sext i32 1 to i64
  %t86 = add nsw i64 %t84, %t85
  store i64 %t86, ptr %pos.addr.18, align 8
  br label %while.cond9
while.end9:
  %t87 = load i64, ptr %pos.addr.18, align 8
  %t88 = load i64, ptr %buf-len.addr.7, align 8
  %t89 = icmp slt i64 %t87, %t88
  br i1 %t89, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t90 = load i64, ptr %pos.addr.18, align 8
  %t91 = sext i32 1 to i64
  %t92 = add nsw i64 %t90, %t91
  store i64 %t92, ptr %pos.addr.18, align 8
  br label %cond.end11
cond.end11:
  br label %cond.end8
cond.end8:
  br label %cond.end7
cond.end7:
  br label %while.cond12
while.cond12:
  %t93 = load i64, ptr %pos.addr.18, align 8
  %t94 = load i64, ptr %buf-len.addr.7, align 8
  %t95 = icmp slt i64 %t93, %t94
  store i1 %t95, ptr %and.val13, align 1
  br i1 %t95, label %and.rhs13, label %and.end13
and.rhs13:
  %t96 = load ptr, ptr %buf.addr.9, align 8
  %t97 = load i64, ptr %pos.addr.18, align 8
  %t98 = call i32 @char-at(ptr %t96, i64 %t97)
  %t99 = icmp ne i32 %t98, 59
  store i1 %t99, ptr %and.val14, align 1
  br i1 %t99, label %and.rhs14, label %and.end14
and.rhs14:
  %t100 = load ptr, ptr %buf.addr.9, align 8
  %t101 = load i64, ptr %pos.addr.18, align 8
  %t102 = call i32 @char-at(ptr %t100, i64 %t101)
  %t103 = icmp ne i32 %t102, 10
  store i1 %t103, ptr %and.val14, align 1
  br label %and.end14
and.end14:
  %t104 = load i1, ptr %and.val14, align 1
  store i1 %t104, ptr %and.val13, align 1
  br label %and.end13
and.end13:
  %t105 = load i1, ptr %and.val13, align 1
  br i1 %t105, label %while.body12, label %while.end12
while.body12:
  %t106 = load ptr, ptr %buf.addr.9, align 8
  %t107 = load i64, ptr %pos.addr.18, align 8
  %t108 = call i32 @char-at(ptr %t106, i64 %t107)
  %t109 = icmp eq i32 %t108, 123
  br i1 %t109, label %cond.then15.0, label %cond.end15
cond.then15.0:
  store i32 1, ptr %brace-depth.addr.110, align 4
  %t111 = load i64, ptr %pos.addr.18, align 8
  %t112 = sext i32 1 to i64
  %t113 = add nsw i64 %t111, %t112
  store i64 %t113, ptr %pos.addr.18, align 8
  br label %while.cond16
while.cond16:
  %t114 = load i64, ptr %pos.addr.18, align 8
  %t115 = load i64, ptr %buf-len.addr.7, align 8
  %t116 = icmp slt i64 %t114, %t115
  store i1 %t116, ptr %and.val17, align 1
  br i1 %t116, label %and.rhs17, label %and.end17
and.rhs17:
  %t117 = load i32, ptr %brace-depth.addr.110, align 4
  %t118 = icmp sgt i32 %t117, 0
  store i1 %t118, ptr %and.val17, align 1
  br label %and.end17
and.end17:
  %t119 = load i1, ptr %and.val17, align 1
  br i1 %t119, label %while.body16, label %while.end16
while.body16:
  %t120 = load ptr, ptr %buf.addr.9, align 8
  %t121 = load i64, ptr %pos.addr.18, align 8
  %t122 = call i32 @char-at(ptr %t120, i64 %t121)
  %t123 = icmp eq i32 %t122, 123
  br i1 %t123, label %cond.then18.0, label %cond.end18
cond.then18.0:
  %t124 = load i32, ptr %brace-depth.addr.110, align 4
  %t125 = add nsw i32 %t124, 1
  store i32 %t125, ptr %brace-depth.addr.110, align 4
  br label %cond.end18
cond.end18:
  %t126 = load ptr, ptr %buf.addr.9, align 8
  %t127 = load i64, ptr %pos.addr.18, align 8
  %t128 = call i32 @char-at(ptr %t126, i64 %t127)
  %t129 = icmp eq i32 %t128, 125
  br i1 %t129, label %cond.then19.0, label %cond.end19
cond.then19.0:
  %t130 = load i32, ptr %brace-depth.addr.110, align 4
  %t131 = sub nsw i32 %t130, 1
  store i32 %t131, ptr %brace-depth.addr.110, align 4
  br label %cond.end19
cond.end19:
  %t132 = load i64, ptr %pos.addr.18, align 8
  %t133 = sext i32 1 to i64
  %t134 = add nsw i64 %t132, %t133
  store i64 %t134, ptr %pos.addr.18, align 8
  br label %while.cond16
while.end16:
  br label %cond.end15
cond.end15:
  %t135 = load i64, ptr %pos.addr.18, align 8
  %t136 = load i64, ptr %buf-len.addr.7, align 8
  %t137 = icmp slt i64 %t135, %t136
  store i1 %t137, ptr %and.val21, align 1
  br i1 %t137, label %and.rhs21, label %and.end21
and.rhs21:
  %t138 = load ptr, ptr %buf.addr.9, align 8
  %t139 = load i64, ptr %pos.addr.18, align 8
  %t140 = call i32 @char-at(ptr %t138, i64 %t139)
  %t141 = icmp ne i32 %t140, 123
  store i1 %t141, ptr %and.val22, align 1
  br i1 %t141, label %and.rhs22, label %and.end22
and.rhs22:
  %t142 = load ptr, ptr %buf.addr.9, align 8
  %t143 = load i64, ptr %pos.addr.18, align 8
  %t144 = call i32 @char-at(ptr %t142, i64 %t143)
  %t145 = icmp ne i32 %t144, 59
  store i1 %t145, ptr %and.val23, align 1
  br i1 %t145, label %and.rhs23, label %and.end23
and.rhs23:
  %t146 = load ptr, ptr %buf.addr.9, align 8
  %t147 = load i64, ptr %pos.addr.18, align 8
  %t148 = call i32 @char-at(ptr %t146, i64 %t147)
  %t149 = icmp ne i32 %t148, 10
  store i1 %t149, ptr %and.val23, align 1
  br label %and.end23
and.end23:
  %t150 = load i1, ptr %and.val23, align 1
  store i1 %t150, ptr %and.val22, align 1
  br label %and.end22
and.end22:
  %t151 = load i1, ptr %and.val22, align 1
  store i1 %t151, ptr %and.val21, align 1
  br label %and.end21
and.end21:
  %t152 = load i1, ptr %and.val21, align 1
  br i1 %t152, label %cond.then20.0, label %cond.end20
cond.then20.0:
  %t153 = load i64, ptr %pos.addr.18, align 8
  %t154 = sext i32 1 to i64
  %t155 = add nsw i64 %t153, %t154
  store i64 %t155, ptr %pos.addr.18, align 8
  br label %cond.end20
cond.end20:
  br label %while.cond12
while.end12:
  %t156 = load i64, ptr %pos.addr.18, align 8
  %t157 = load i64, ptr %buf-len.addr.7, align 8
  %t158 = icmp slt i64 %t156, %t157
  br i1 %t158, label %cond.then24.0, label %cond.end24
cond.then24.0:
  %t159 = load i64, ptr %pos.addr.18, align 8
  %t160 = sext i32 1 to i64
  %t161 = add nsw i64 %t159, %t160
  store i64 %t161, ptr %pos.addr.18, align 8
  br label %cond.end24
cond.end24:
  br label %cond.end3
cond.end3:
  br label %cond.end2
cond.end2:
  %t162 = load i64, ptr %pos.addr.18, align 8
  %t163 = load i64, ptr %prev-pos.addr.20, align 8
  %t164 = icmp eq i64 %t162, %t163
  br i1 %t164, label %cond.then25.0, label %cond.end25
cond.then25.0:
  %t165 = load i64, ptr %pos.addr.18, align 8
  %t166 = sext i32 1 to i64
  %t167 = add nsw i64 %t165, %t166
  store i64 %t167, ptr %pos.addr.18, align 8
  br label %cond.end25
cond.end25:
  br label %while.cond1
while.end1:
  %t168 = load ptr, ptr %buf.addr.9, align 8
  call void @free(ptr %t168)
  %t169 = load ptr, ptr @g-out, align 8
  %t170 = getelementptr inbounds [2 x i8], ptr @.str.453, i64 0, i64 0
  %t171 = call i32 (ptr, ptr, ...) @fprintf(ptr %t169, ptr %t170)
  ret void
}

define void @emit-defn(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %name-node.addr.9 = alloca ptr, align 8
  %params-node.addr.12 = alloca ptr, align 8
  %fname.addr.22 = alloca ptr, align 8
  %ret-name.addr.23 = alloca ptr, align 8
  %ret.addr.33 = alloca ptr, align 8
  %nparams.addr.39 = alloca i32, align 4
  %param-types.addr.42 = alloca ptr, align 8
  %param-names.addr.43 = alloca ptr, align 8
  %i.addr.56 = alloca i32, align 4
  %p.addr.60 = alloca ptr, align 8
  %pname.addr.64 = alloca ptr, align 8
  %pty.addr.65 = alloca ptr, align 8
  %ft.addr.91 = alloca ptr, align 8
  %fn-scope.addr.111 = alloca ptr, align 8
  %i.addr.114 = alloca i32, align 4
  %pname.addr.118 = alloca ptr, align 8
  %ptype.addr.124 = alloca ptr, align 8
  %slot.addr.130 = alloca ptr, align 8
  %arg.addr.134 = alloca ptr, align 8
  %palign.addr.138 = alloca i32, align 4
  %zero.addr.183 = alloca ptr, align 8
  %and.val14 = alloca i1, align 1
  %and.val16 = alloca i1, align 1
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
  %t8 = getelementptr inbounds [15 x i8], ptr @.str.454, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %name-node.addr.9, align 8
  %t13 = load ptr, ptr %cc.addr.0, align 8
  %t14 = call ptr @node-at(ptr %t13, i32 2)
  store ptr %t14, ptr %params-node.addr.12, align 8
  %t15 = load ptr, ptr %params-node.addr.12, align 8
  %t16 = call i32 @node-is-list(ptr %t15)
  %t17 = icmp eq i32 %t16, 0
  br i1 %t17, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t18 = load ptr, ptr %name-node.addr.9, align 8
  %t19 = getelementptr inbounds %Node, ptr %t18, i32 0, i32 1
  %t20 = load i32, ptr %t19, align 4
  %t21 = getelementptr inbounds [26 x i8], ptr @.str.455, i64 0, i64 0
  call void @die-at(i32 %t20, ptr %t21)
  br label %cond.end1
cond.end1:
  store ptr null, ptr %fname.addr.22, align 8
  store ptr null, ptr %ret-name.addr.23, align 8
  %t24 = load ptr, ptr %name-node.addr.9, align 8
  call void @extract-name-type(ptr %t24, ptr %fname.addr.22, ptr %ret-name.addr.23)
  %t25 = load ptr, ptr %ret-name.addr.23, align 8
  %t26 = icmp eq ptr %t25, null
  br i1 %t26, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t27 = load ptr, ptr %name-node.addr.9, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 1
  %t29 = load i32, ptr %t28, align 4
  %t30 = getelementptr inbounds [28 x i8], ptr @.str.456, i64 0, i64 0
  %t31 = load ptr, ptr %fname.addr.22, align 8
  %t32 = call ptr @fmt-s(ptr %t30, ptr %t31)
  call void @die-at(i32 %t29, ptr %t32)
  br label %cond.end2
cond.end2:
  %t34 = load ptr, ptr %ret-name.addr.23, align 8
  %t35 = load ptr, ptr %name-node.addr.9, align 8
  %t36 = getelementptr inbounds %Node, ptr %t35, i32 0, i32 1
  %t37 = load i32, ptr %t36, align 4
  %t38 = call ptr @parse-type-name(ptr %t34, i32 %t37)
  store ptr %t38, ptr %ret.addr.33, align 8
  %t40 = load ptr, ptr %params-node.addr.12, align 8
  %t41 = call i32 @node-len(ptr %t40)
  store i32 %t41, ptr %nparams.addr.39, align 4
  store ptr null, ptr %param-types.addr.42, align 8
  store ptr null, ptr %param-names.addr.43, align 8
  %t44 = load i32, ptr %nparams.addr.39, align 4
  %t45 = icmp sgt i32 %t44, 0
  br i1 %t45, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t46 = load i32, ptr %nparams.addr.39, align 4
  %t47 = call i64 @i64(i32 %t46)
  %t48 = call i64 @i64(i32 8)
  %t49 = mul nsw i64 %t47, %t48
  %t50 = call ptr @arena-alloc(i64 %t49)
  store ptr %t50, ptr %param-types.addr.42, align 8
  %t51 = load i32, ptr %nparams.addr.39, align 4
  %t52 = call i64 @i64(i32 %t51)
  %t53 = call i64 @i64(i32 8)
  %t54 = mul nsw i64 %t52, %t53
  %t55 = call ptr @arena-alloc(i64 %t54)
  store ptr %t55, ptr %param-names.addr.43, align 8
  br label %cond.end3
cond.end3:
  store i32 0, ptr %i.addr.56, align 4
  br label %while.cond4
while.cond4:
  %t57 = load i32, ptr %i.addr.56, align 4
  %t58 = load i32, ptr %nparams.addr.39, align 4
  %t59 = icmp slt i32 %t57, %t58
  br i1 %t59, label %while.body4, label %while.end4
while.body4:
  %t61 = load ptr, ptr %params-node.addr.12, align 8
  %t62 = load i32, ptr %i.addr.56, align 4
  %t63 = call ptr @node-at(ptr %t61, i32 %t62)
  store ptr %t63, ptr %p.addr.60, align 8
  store ptr null, ptr %pname.addr.64, align 8
  %t66 = load ptr, ptr %p.addr.60, align 8
  %t67 = load ptr, ptr %p.addr.60, align 8
  %t68 = getelementptr inbounds %Node, ptr %t67, i32 0, i32 1
  %t69 = load i32, ptr %t68, align 4
  %t70 = call ptr @extract-name-and-type(ptr %t66, ptr %pname.addr.64, i32 %t69)
  store ptr %t70, ptr %pty.addr.65, align 8
  %t71 = load ptr, ptr %pty.addr.65, align 8
  %t72 = icmp eq ptr %t71, null
  br i1 %t72, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t73 = load ptr, ptr %p.addr.60, align 8
  %t74 = getelementptr inbounds %Node, ptr %t73, i32 0, i32 1
  %t75 = load i32, ptr %t74, align 4
  %t76 = getelementptr inbounds [34 x i8], ptr @.str.457, i64 0, i64 0
  %t77 = load ptr, ptr %pname.addr.64, align 8
  %t78 = call ptr @fmt-s(ptr %t76, ptr %t77)
  call void @die-at(i32 %t75, ptr %t78)
  br label %cond.end5
cond.end5:
  %t79 = load ptr, ptr %param-types.addr.42, align 8
  %t80 = load i32, ptr %i.addr.56, align 4
  %t81 = sext i32 %t80 to i64
  %t82 = load ptr, ptr %pty.addr.65, align 8
  %t83 = getelementptr inbounds ptr, ptr %t79, i64 %t81
  store ptr %t82, ptr %t83, align 8
  %t84 = load ptr, ptr %param-names.addr.43, align 8
  %t85 = load i32, ptr %i.addr.56, align 4
  %t86 = sext i32 %t85 to i64
  %t87 = load ptr, ptr %pname.addr.64, align 8
  %t88 = getelementptr inbounds ptr, ptr %t84, i64 %t86
  store ptr %t87, ptr %t88, align 8
  %t89 = load i32, ptr %i.addr.56, align 4
  %t90 = add nsw i32 %t89, 1
  store i32 %t90, ptr %i.addr.56, align 4
  br label %while.cond4
while.end4:
  %t92 = call ptr @make-type(i32 11)
  store ptr %t92, ptr %ft.addr.91, align 8
  %t93 = load ptr, ptr %ft.addr.91, align 8
  %t94 = load ptr, ptr %ret.addr.33, align 8
  %t95 = getelementptr inbounds %Type, ptr %t93, i32 0, i32 1
  store ptr %t94, ptr %t95, align 8
  %t96 = load ptr, ptr %ft.addr.91, align 8
  %t97 = load i32, ptr %nparams.addr.39, align 4
  %t98 = getelementptr inbounds %Type, ptr %t96, i32 0, i32 3
  store i32 %t97, ptr %t98, align 4
  %t99 = load ptr, ptr %ft.addr.91, align 8
  %t100 = load ptr, ptr %param-types.addr.42, align 8
  %t101 = getelementptr inbounds %Type, ptr %t99, i32 0, i32 2
  store ptr %t100, ptr %t101, align 8
  %t102 = load ptr, ptr %ft.addr.91, align 8
  %t103 = getelementptr inbounds %Type, ptr %t102, i32 0, i32 4
  store i32 0, ptr %t103, align 4
  %t104 = load ptr, ptr @g-globals, align 8
  %t105 = load ptr, ptr %fname.addr.22, align 8
  %t106 = load ptr, ptr %ft.addr.91, align 8
  %t107 = getelementptr inbounds [4 x i8], ptr @.str.458, i64 0, i64 0
  %t108 = load ptr, ptr %fname.addr.22, align 8
  %t109 = call ptr @fmt-s(ptr %t107, ptr %t108)
  %t110 = call ptr @scope-define(ptr %t104, ptr %t105, ptr %t106, ptr %t109, i32 0)
  call void @reset-function-state()
  %t112 = load ptr, ptr @g-globals, align 8
  %t113 = call ptr @scope-new(ptr %t112)
  store ptr %t113, ptr %fn-scope.addr.111, align 8
  store i32 0, ptr %i.addr.114, align 4
  br label %while.cond6
while.cond6:
  %t115 = load i32, ptr %i.addr.114, align 4
  %t116 = load i32, ptr %nparams.addr.39, align 4
  %t117 = icmp slt i32 %t115, %t116
  br i1 %t117, label %while.body6, label %while.end6
while.body6:
  %t119 = load ptr, ptr %param-names.addr.43, align 8
  %t120 = load i32, ptr %i.addr.114, align 4
  %t121 = sext i32 %t120 to i64
  %t122 = getelementptr inbounds ptr, ptr %t119, i64 %t121
  %t123 = load ptr, ptr %t122, align 8
  store ptr %t123, ptr %pname.addr.118, align 8
  %t125 = load ptr, ptr %param-types.addr.42, align 8
  %t126 = load i32, ptr %i.addr.114, align 4
  %t127 = sext i32 %t126 to i64
  %t128 = getelementptr inbounds ptr, ptr %t125, i64 %t127
  %t129 = load ptr, ptr %t128, align 8
  store ptr %t129, ptr %ptype.addr.124, align 8
  %t131 = getelementptr inbounds [10 x i8], ptr @.str.459, i64 0, i64 0
  %t132 = load ptr, ptr %pname.addr.118, align 8
  %t133 = call ptr @fmt-s(ptr %t131, ptr %t132)
  store ptr %t133, ptr %slot.addr.130, align 8
  %t135 = getelementptr inbounds [9 x i8], ptr @.str.460, i64 0, i64 0
  %t136 = load ptr, ptr %pname.addr.118, align 8
  %t137 = call ptr @fmt-s(ptr %t135, ptr %t136)
  store ptr %t137, ptr %arg.addr.134, align 8
  %t139 = load ptr, ptr %ptype.addr.124, align 8
  %t140 = call i32 @type-size(ptr %t139)
  store i32 %t140, ptr %palign.addr.138, align 4
  %t141 = load ptr, ptr @g-entry-stream, align 8
  %t142 = getelementptr inbounds [28 x i8], ptr @.str.461, i64 0, i64 0
  %t143 = load ptr, ptr %slot.addr.130, align 8
  %t144 = load ptr, ptr %ptype.addr.124, align 8
  %t145 = call ptr @type-to-ir(ptr %t144)
  %t146 = load i32, ptr %palign.addr.138, align 4
  %t147 = call i32 (ptr, ptr, ...) @fprintf(ptr %t141, ptr %t142, ptr %t143, ptr %t145, i32 %t146)
  %t148 = load ptr, ptr @g-entry-stream, align 8
  %t149 = getelementptr inbounds [33 x i8], ptr @.str.462, i64 0, i64 0
  %t150 = load ptr, ptr %ptype.addr.124, align 8
  %t151 = call ptr @type-to-ir(ptr %t150)
  %t152 = load ptr, ptr %arg.addr.134, align 8
  %t153 = load ptr, ptr %slot.addr.130, align 8
  %t154 = load i32, ptr %palign.addr.138, align 4
  %t155 = call i32 (ptr, ptr, ...) @fprintf(ptr %t148, ptr %t149, ptr %t151, ptr %t152, ptr %t153, i32 %t154)
  %t156 = load ptr, ptr %fn-scope.addr.111, align 8
  %t157 = load ptr, ptr %pname.addr.118, align 8
  %t158 = load ptr, ptr %ptype.addr.124, align 8
  %t159 = load ptr, ptr %slot.addr.130, align 8
  %t160 = call ptr @scope-define(ptr %t156, ptr %t157, ptr %t158, ptr %t159, i32 1)
  %t161 = load i32, ptr %i.addr.114, align 4
  %t162 = add nsw i32 %t161, 1
  store i32 %t162, ptr %i.addr.114, align 4
  br label %while.cond6
while.end6:
  store i32 3, ptr %i.addr.114, align 4
  br label %while.cond7
while.cond7:
  %t163 = load i32, ptr %i.addr.114, align 4
  %t164 = load ptr, ptr %cc.addr.0, align 8
  %t165 = call i32 @node-len(ptr %t164)
  %t166 = icmp slt i32 %t163, %t165
  br i1 %t166, label %while.body7, label %while.end7
while.body7:
  %t167 = load ptr, ptr %cc.addr.0, align 8
  %t168 = load i32, ptr %i.addr.114, align 4
  %t169 = call ptr @node-at(ptr %t167, i32 %t168)
  %t170 = load ptr, ptr %fn-scope.addr.111, align 8
  %t171 = call ptr @emit-node(ptr %t169, ptr %t170)
  %t172 = load i32, ptr %i.addr.114, align 4
  %t173 = add nsw i32 %t172, 1
  store i32 %t173, ptr %i.addr.114, align 4
  br label %while.cond7
while.end7:
  %t174 = load i32, ptr @g-block-term, align 4
  %t175 = icmp eq i32 %t174, 0
  br i1 %t175, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t176 = load ptr, ptr %ret.addr.33, align 8
  %t177 = getelementptr inbounds %Type, ptr %t176, i32 0, i32 0
  %t178 = load i32, ptr %t177, align 4
  %t179 = icmp eq i32 %t178, 0
  br i1 %t179, label %cond.then9.0, label %cond.test9.1
cond.then9.0:
  %t180 = load ptr, ptr @g-body-stream, align 8
  %t181 = getelementptr inbounds [12 x i8], ptr @.str.463, i64 0, i64 0
  %t182 = call i32 (ptr, ptr, ...) @fprintf(ptr %t180, ptr %t181)
  br label %cond.end9
cond.test9.1:
  br i1 1, label %cond.then9.1, label %cond.end9
cond.then9.1:
  %t184 = getelementptr inbounds [2 x i8], ptr @.str.464, i64 0, i64 0
  store ptr %t184, ptr %zero.addr.183, align 8
  %t185 = load ptr, ptr %ret.addr.33, align 8
  %t186 = getelementptr inbounds %Type, ptr %t185, i32 0, i32 0
  %t187 = load i32, ptr %t186, align 4
  %t188 = icmp eq i32 %t187, 10
  br i1 %t188, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t189 = getelementptr inbounds [5 x i8], ptr @.str.465, i64 0, i64 0
  store ptr %t189, ptr %zero.addr.183, align 8
  br label %cond.end10
cond.end10:
  %t190 = load ptr, ptr @g-body-stream, align 8
  %t191 = getelementptr inbounds [13 x i8], ptr @.str.466, i64 0, i64 0
  %t192 = load ptr, ptr %ret.addr.33, align 8
  %t193 = call ptr @type-to-ir(ptr %t192)
  %t194 = load ptr, ptr %zero.addr.183, align 8
  %t195 = call i32 (ptr, ptr, ...) @fprintf(ptr %t190, ptr %t191, ptr %t193, ptr %t194)
  br label %cond.end9
cond.end9:
  br label %cond.end8
cond.end8:
  %t196 = load ptr, ptr @g-entry-stream, align 8
  %t197 = call i32 @fclose(ptr %t196)
  %t198 = load ptr, ptr @g-body-stream, align 8
  %t199 = call i32 @fclose(ptr %t198)
  %t200 = load ptr, ptr @g-out, align 8
  %t201 = getelementptr inbounds [15 x i8], ptr @.str.467, i64 0, i64 0
  %t202 = load ptr, ptr %ret.addr.33, align 8
  %t203 = call ptr @type-to-ir(ptr %t202)
  %t204 = load ptr, ptr %fname.addr.22, align 8
  %t205 = call i32 (ptr, ptr, ...) @fprintf(ptr %t200, ptr %t201, ptr %t203, ptr %t204)
  store i32 0, ptr %i.addr.114, align 4
  br label %while.cond11
while.cond11:
  %t206 = load i32, ptr %i.addr.114, align 4
  %t207 = load i32, ptr %nparams.addr.39, align 4
  %t208 = icmp slt i32 %t206, %t207
  br i1 %t208, label %while.body11, label %while.end11
while.body11:
  %t209 = load i32, ptr %i.addr.114, align 4
  %t210 = icmp ne i32 %t209, 0
  br i1 %t210, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t211 = load ptr, ptr @g-out, align 8
  %t212 = getelementptr inbounds [3 x i8], ptr @.str.468, i64 0, i64 0
  %t213 = call i32 (ptr, ptr, ...) @fprintf(ptr %t211, ptr %t212)
  br label %cond.end12
cond.end12:
  %t214 = load ptr, ptr @g-out, align 8
  %t215 = getelementptr inbounds [12 x i8], ptr @.str.469, i64 0, i64 0
  %t216 = load ptr, ptr %param-types.addr.42, align 8
  %t217 = load i32, ptr %i.addr.114, align 4
  %t218 = sext i32 %t217 to i64
  %t219 = getelementptr inbounds ptr, ptr %t216, i64 %t218
  %t220 = load ptr, ptr %t219, align 8
  %t221 = call ptr @type-to-ir(ptr %t220)
  %t222 = load ptr, ptr %param-names.addr.43, align 8
  %t223 = load i32, ptr %i.addr.114, align 4
  %t224 = sext i32 %t223 to i64
  %t225 = getelementptr inbounds ptr, ptr %t222, i64 %t224
  %t226 = load ptr, ptr %t225, align 8
  %t227 = call i32 (ptr, ptr, ...) @fprintf(ptr %t214, ptr %t215, ptr %t221, ptr %t226)
  %t228 = load i32, ptr %i.addr.114, align 4
  %t229 = add nsw i32 %t228, 1
  store i32 %t229, ptr %i.addr.114, align 4
  br label %while.cond11
while.end11:
  %t230 = load ptr, ptr @g-out, align 8
  %t231 = getelementptr inbounds [5 x i8], ptr @.str.470, i64 0, i64 0
  %t232 = call i32 (ptr, ptr, ...) @fprintf(ptr %t230, ptr %t231)
  %t233 = load ptr, ptr @g-out, align 8
  %t234 = getelementptr inbounds [8 x i8], ptr @.str.471, i64 0, i64 0
  %t235 = call i32 (ptr, ptr, ...) @fprintf(ptr %t233, ptr %t234)
  %t236 = load ptr, ptr @g-entry-bufp, align 8
  %t237 = icmp ne ptr %t236, null
  store i1 %t237, ptr %and.val14, align 1
  br i1 %t237, label %and.rhs14, label %and.end14
and.rhs14:
  %t238 = load ptr, ptr @g-entry-bufp, align 8
  %t239 = sext i32 0 to i64
  %t240 = call i32 @char-at(ptr %t238, i64 %t239)
  %t241 = icmp ne i32 %t240, 0
  store i1 %t241, ptr %and.val14, align 1
  br label %and.end14
and.end14:
  %t242 = load i1, ptr %and.val14, align 1
  br i1 %t242, label %cond.then13.0, label %cond.end13
cond.then13.0:
  %t243 = load ptr, ptr @g-entry-bufp, align 8
  %t244 = load ptr, ptr @g-out, align 8
  %t245 = call i32 @fputs(ptr %t243, ptr %t244)
  br label %cond.end13
cond.end13:
  %t246 = load ptr, ptr @g-body-bufp, align 8
  %t247 = icmp ne ptr %t246, null
  store i1 %t247, ptr %and.val16, align 1
  br i1 %t247, label %and.rhs16, label %and.end16
and.rhs16:
  %t248 = load ptr, ptr @g-body-bufp, align 8
  %t249 = sext i32 0 to i64
  %t250 = call i32 @char-at(ptr %t248, i64 %t249)
  %t251 = icmp ne i32 %t250, 0
  store i1 %t251, ptr %and.val16, align 1
  br label %and.end16
and.end16:
  %t252 = load i1, ptr %and.val16, align 1
  br i1 %t252, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t253 = load ptr, ptr @g-body-bufp, align 8
  %t254 = load ptr, ptr @g-out, align 8
  %t255 = call i32 @fputs(ptr %t253, ptr %t254)
  br label %cond.end15
cond.end15:
  %t256 = load ptr, ptr @g-out, align 8
  %t257 = getelementptr inbounds [4 x i8], ptr @.str.472, i64 0, i64 0
  %t258 = call i32 (ptr, ptr, ...) @fprintf(ptr %t256, ptr %t257)
  %t259 = load ptr, ptr @g-entry-bufp, align 8
  call void @free(ptr %t259)
  %t260 = load ptr, ptr @g-body-bufp, align 8
  call void @free(ptr %t260)
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
  %prefix.addr.19 = alloca i8, align 1
  %gen.addr.22 = alloca ptr, align 8
  %err.addr.23 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [44 x i8], ptr @.str.473, i64 0, i64 0
  %t9 = load ptr, ptr @g-source-path, align 8
  %t10 = load i32, ptr %line.addr, align 4
  %t11 = load ptr, ptr %err.addr.3, align 8
  %t12 = call ptr @LLVMGetErrorMessage(ptr %t11)
  %t13 = call i32 (ptr, ptr, ...) @fprintf(ptr %t7, ptr %t8, ptr %t9, i32 %t10, ptr %t12)
  %t14 = load i32, ptr @g-interactive, align 4
  %t15 = icmp ne i32 %t14, 0
  br i1 %t15, label %cond.then2.0, label %cond.end2
cond.then2.0:
  call void @repl_throw()
  br label %cond.end2
cond.end2:
  call void @exit(i32 1)
  br label %cond.end1
cond.end1:
  %t16 = load ptr, ptr %jit-ref.addr.2, align 8
  store ptr %t16, ptr @g-jit, align 8
  %t17 = load ptr, ptr @g-jit, align 8
  %t18 = call ptr @LLVMOrcLLJITGetMainJITDylib(ptr %t17)
  store ptr %t18, ptr @g-jit-dylib, align 8
  %t20 = load ptr, ptr @g-jit, align 8
  %t21 = call i8 @LLVMOrcLLJITGetGlobalPrefix(ptr %t20)
  store i8 %t21, ptr %prefix.addr.19, align 1
  store ptr null, ptr %gen.addr.22, align 8
  %t24 = load i8, ptr %prefix.addr.19, align 1
  %t25 = call ptr @LLVMOrcCreateDynamicLibrarySearchGeneratorForProcess(ptr %gen.addr.22, i8 %t24, ptr null, ptr null)
  store ptr %t25, ptr %err.addr.23, align 8
  %t26 = load ptr, ptr %err.addr.23, align 8
  %t27 = icmp ne ptr %t26, null
  br i1 %t27, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t28 = load ptr, ptr @stderr, align 8
  %t29 = getelementptr inbounds [47 x i8], ptr @.str.474, i64 0, i64 0
  %t30 = load ptr, ptr @g-source-path, align 8
  %t31 = load i32, ptr %line.addr, align 4
  %t32 = load ptr, ptr %err.addr.23, align 8
  %t33 = call ptr @LLVMGetErrorMessage(ptr %t32)
  %t34 = call i32 (ptr, ptr, ...) @fprintf(ptr %t28, ptr %t29, ptr %t30, i32 %t31, ptr %t33)
  %t35 = load i32, ptr @g-interactive, align 4
  %t36 = icmp ne i32 %t35, 0
  br i1 %t36, label %cond.then4.0, label %cond.end4
cond.then4.0:
  call void @repl_throw()
  br label %cond.end4
cond.end4:
  call void @exit(i32 1)
  br label %cond.end3
cond.end3:
  %t37 = load ptr, ptr @g-jit-dylib, align 8
  %t38 = load ptr, ptr %gen.addr.22, align 8
  call void @LLVMOrcJITDylibAddGenerator(ptr %t37, ptr %t38)
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
  %tsctx.addr.27 = alloca ptr, align 8
  %tsmod.addr.29 = alloca ptr, align 8
  %err.addr.34 = alloca ptr, align 8
  %t0 = load i32, ptr %line.addr, align 4
  call void @jit-ensure-init(i32 %t0)
  %t2 = call ptr @LLVMContextCreate()
  store ptr %t2, ptr %ctx.addr.1, align 8
  %t4 = load ptr, ptr %ir.addr, align 8
  %t5 = call i64 @strlen(ptr %t4)
  store i64 %t5, ptr %ir-len.addr.3, align 8
  %t7 = load ptr, ptr %ir.addr, align 8
  %t8 = load i64, ptr %ir-len.addr.3, align 8
  %t9 = getelementptr inbounds [15 x i8], ptr @.str.475, i64 0, i64 0
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
  %t20 = getelementptr inbounds [41 x i8], ptr @.str.476, i64 0, i64 0
  %t21 = load ptr, ptr @g-source-path, align 8
  %t22 = load i32, ptr %line.addr, align 4
  %t23 = load ptr, ptr %errmsg.addr.12, align 8
  %t24 = call i32 (ptr, ptr, ...) @fprintf(ptr %t19, ptr %t20, ptr %t21, i32 %t22, ptr %t23)
  %t25 = load i32, ptr @g-interactive, align 4
  %t26 = icmp ne i32 %t25, 0
  br i1 %t26, label %cond.then1.0, label %cond.end1
cond.then1.0:
  call void @repl_throw()
  br label %cond.end1
cond.end1:
  call void @exit(i32 1)
  br label %cond.end0
cond.end0:
  %t28 = call ptr @LLVMOrcCreateNewThreadSafeContext()
  store ptr %t28, ptr %tsctx.addr.27, align 8
  %t30 = load ptr, ptr %mod.addr.11, align 8
  %t31 = load ptr, ptr %tsctx.addr.27, align 8
  %t32 = call ptr @LLVMOrcCreateNewThreadSafeModule(ptr %t30, ptr %t31)
  store ptr %t32, ptr %tsmod.addr.29, align 8
  %t33 = load ptr, ptr %tsctx.addr.27, align 8
  call void @LLVMOrcDisposeThreadSafeContext(ptr %t33)
  %t35 = load ptr, ptr @g-jit, align 8
  %t36 = load ptr, ptr @g-jit-dylib, align 8
  %t37 = load ptr, ptr %tsmod.addr.29, align 8
  %t38 = call ptr @LLVMOrcLLJITAddLLVMIRModule(ptr %t35, ptr %t36, ptr %t37)
  store ptr %t38, ptr %err.addr.34, align 8
  %t39 = load ptr, ptr %err.addr.34, align 8
  %t40 = icmp ne ptr %t39, null
  br i1 %t40, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t41 = load ptr, ptr @stderr, align 8
  %t42 = getelementptr inbounds [41 x i8], ptr @.str.477, i64 0, i64 0
  %t43 = load ptr, ptr @g-source-path, align 8
  %t44 = load i32, ptr %line.addr, align 4
  %t45 = load ptr, ptr %err.addr.34, align 8
  %t46 = call ptr @LLVMGetErrorMessage(ptr %t45)
  %t47 = call i32 (ptr, ptr, ...) @fprintf(ptr %t41, ptr %t42, ptr %t43, i32 %t44, ptr %t46)
  %t48 = load i32, ptr @g-interactive, align 4
  %t49 = icmp ne i32 %t48, 0
  br i1 %t49, label %cond.then3.0, label %cond.end3
cond.then3.0:
  call void @repl_throw()
  br label %cond.end3
cond.end3:
  call void @exit(i32 1)
  br label %cond.end2
cond.end2:
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
  %fname.addr.79 = alloca ptr, align 8
  %ret-name.addr.80 = alloca ptr, align 8
  %ret.addr.84 = alloca ptr, align 8
  %nparams.addr.90 = alloca i32, align 4
  %ptypes.addr.93 = alloca ptr, align 8
  %j.addr.101 = alloca i32, align 4
  %p.addr.105 = alloca ptr, align 8
  %pn.addr.109 = alloca ptr, align 8
  %pt-name.addr.110 = alloca ptr, align 8
  %ft.addr.130 = alloca ptr, align 8
  %expr-forms.addr.150 = alloca ptr, align 8
  %nexpr.addr.155 = alloca i32, align 4
  %bi.addr.156 = alloca i32, align 4
  %bf.addr.160 = alloca ptr, align 8
  %is-tl.addr.164 = alloca i32, align 4
  %and.val14 = alloca i1, align 1
  %and.val15 = alloca i1, align 1
  %and.val16 = alloca i1, align 1
  %bh.addr.182 = alloca ptr, align 8
  %and.val25 = alloca i1, align 1
  %ct-sym.addr.241 = alloca ptr, align 8
  %fn-scope.addr.249 = alloca ptr, align 8
  %ei.addr.252 = alloca i32, align 4
  %and.val29 = alloca i1, align 1
  %and.val31 = alloca i1, align 1
  %ct-qq.addr.306 = alloca i32, align 4
  %ir-bufp.addr.397 = alloca ptr, align 8
  %ir-sizep.addr.398 = alloca i64, align 8
  %irs.addr.400 = alloca ptr, align 8
  %and.val35 = alloca i1, align 1
  %and.val37 = alloca i1, align 1
  %and.val39 = alloca i1, align 1
  %and.val41 = alloca i1, align 1
  %and.val43 = alloca i1, align 1
  %and.val45 = alloca i1, align 1
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
  %t10 = getelementptr inbounds [46 x i8], ptr @.str.478, i64 0, i64 0
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
  %t63 = getelementptr inbounds [5 x i8], ptr @.str.479, i64 0, i64 0
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
  %t76 = load ptr, ptr %params-node.addr.73, align 8
  %t77 = call i32 @node-is-list(ptr %t76)
  %t78 = icmp ne i32 %t77, 0
  br i1 %t78, label %cond.then7.0, label %cond.end7
cond.then7.0:
  store ptr null, ptr %fname.addr.79, align 8
  store ptr null, ptr %ret-name.addr.80, align 8
  %t81 = load ptr, ptr %name-node.addr.70, align 8
  call void @extract-name-type(ptr %t81, ptr %fname.addr.79, ptr %ret-name.addr.80)
  %t82 = load ptr, ptr %ret-name.addr.80, align 8
  %t83 = icmp ne ptr %t82, null
  br i1 %t83, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t85 = load ptr, ptr %ret-name.addr.80, align 8
  %t86 = load ptr, ptr %name-node.addr.70, align 8
  %t87 = getelementptr inbounds %Node, ptr %t86, i32 0, i32 1
  %t88 = load i32, ptr %t87, align 4
  %t89 = call ptr @parse-type-name(ptr %t85, i32 %t88)
  store ptr %t89, ptr %ret.addr.84, align 8
  %t91 = load ptr, ptr %params-node.addr.73, align 8
  %t92 = call i32 @node-len(ptr %t91)
  store i32 %t92, ptr %nparams.addr.90, align 4
  store ptr null, ptr %ptypes.addr.93, align 8
  %t94 = load i32, ptr %nparams.addr.90, align 4
  %t95 = icmp sgt i32 %t94, 0
  br i1 %t95, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t96 = load i32, ptr %nparams.addr.90, align 4
  %t97 = call i64 @i64(i32 %t96)
  %t98 = call i64 @i64(i32 8)
  %t99 = mul nsw i64 %t97, %t98
  %t100 = call ptr @arena-alloc(i64 %t99)
  store ptr %t100, ptr %ptypes.addr.93, align 8
  br label %cond.end9
cond.end9:
  store i32 0, ptr %j.addr.101, align 4
  br label %while.cond10
while.cond10:
  %t102 = load i32, ptr %j.addr.101, align 4
  %t103 = load i32, ptr %nparams.addr.90, align 4
  %t104 = icmp slt i32 %t102, %t103
  br i1 %t104, label %while.body10, label %while.end10
while.body10:
  %t106 = load ptr, ptr %params-node.addr.73, align 8
  %t107 = load i32, ptr %j.addr.101, align 4
  %t108 = call ptr @node-at(ptr %t106, i32 %t107)
  store ptr %t108, ptr %p.addr.105, align 8
  store ptr null, ptr %pn.addr.109, align 8
  store ptr null, ptr %pt-name.addr.110, align 8
  %t111 = load ptr, ptr %p.addr.105, align 8
  call void @extract-name-type(ptr %t111, ptr %pn.addr.109, ptr %pt-name.addr.110)
  %t112 = load ptr, ptr %pt-name.addr.110, align 8
  %t113 = icmp ne ptr %t112, null
  br i1 %t113, label %cond.then11.0, label %cond.test11.1
cond.then11.0:
  %t114 = load ptr, ptr %ptypes.addr.93, align 8
  %t115 = load i32, ptr %j.addr.101, align 4
  %t116 = sext i32 %t115 to i64
  %t117 = load ptr, ptr %pt-name.addr.110, align 8
  %t118 = load ptr, ptr %p.addr.105, align 8
  %t119 = getelementptr inbounds %Node, ptr %t118, i32 0, i32 1
  %t120 = load i32, ptr %t119, align 4
  %t121 = call ptr @parse-type-name(ptr %t117, i32 %t120)
  %t122 = getelementptr inbounds ptr, ptr %t114, i64 %t116
  store ptr %t121, ptr %t122, align 8
  br label %cond.end11
cond.test11.1:
  br i1 1, label %cond.then11.1, label %cond.end11
cond.then11.1:
  %t123 = load ptr, ptr %ptypes.addr.93, align 8
  %t124 = load i32, ptr %j.addr.101, align 4
  %t125 = sext i32 %t124 to i64
  %t126 = load ptr, ptr @ty-i32, align 8
  %t127 = getelementptr inbounds ptr, ptr %t123, i64 %t125
  store ptr %t126, ptr %t127, align 8
  br label %cond.end11
cond.end11:
  %t128 = load i32, ptr %j.addr.101, align 4
  %t129 = add nsw i32 %t128, 1
  store i32 %t129, ptr %j.addr.101, align 4
  br label %while.cond10
while.end10:
  %t131 = call ptr @make-type(i32 11)
  store ptr %t131, ptr %ft.addr.130, align 8
  %t132 = load ptr, ptr %ft.addr.130, align 8
  %t133 = load ptr, ptr %ret.addr.84, align 8
  %t134 = getelementptr inbounds %Type, ptr %t132, i32 0, i32 1
  store ptr %t133, ptr %t134, align 8
  %t135 = load ptr, ptr %ft.addr.130, align 8
  %t136 = load i32, ptr %nparams.addr.90, align 4
  %t137 = getelementptr inbounds %Type, ptr %t135, i32 0, i32 3
  store i32 %t136, ptr %t137, align 4
  %t138 = load ptr, ptr %ft.addr.130, align 8
  %t139 = load ptr, ptr %ptypes.addr.93, align 8
  %t140 = getelementptr inbounds %Type, ptr %t138, i32 0, i32 2
  store ptr %t139, ptr %t140, align 8
  %t141 = load ptr, ptr @g-globals, align 8
  %t142 = load ptr, ptr %fname.addr.79, align 8
  %t143 = load ptr, ptr %ft.addr.130, align 8
  %t144 = getelementptr inbounds [4 x i8], ptr @.str.480, i64 0, i64 0
  %t145 = load ptr, ptr %fname.addr.79, align 8
  %t146 = call ptr @fmt-s(ptr %t144, ptr %t145)
  %t147 = call ptr @scope-define(ptr %t141, ptr %t142, ptr %t143, ptr %t146, i32 0)
  br label %cond.end8
cond.end8:
  br label %cond.end7
cond.end7:
  br label %cond.end2
cond.end2:
  %t148 = load i32, ptr %bi.addr.37, align 4
  %t149 = add nsw i32 %t148, 1
  store i32 %t149, ptr %bi.addr.37, align 4
  br label %while.cond1
while.end1:
  %t151 = sext i32 256 to i64
  %t152 = sext i32 8 to i64
  %t153 = mul nsw i64 %t151, %t152
  %t154 = call ptr @arena-alloc(i64 %t153)
  store ptr %t154, ptr %expr-forms.addr.150, align 8
  store i32 0, ptr %nexpr.addr.155, align 4
  store i32 1, ptr %bi.addr.156, align 4
  br label %while.cond12
while.cond12:
  %t157 = load i32, ptr %bi.addr.156, align 4
  %t158 = load i32, ptr %nforms.addr.0, align 4
  %t159 = icmp slt i32 %t157, %t158
  br i1 %t159, label %while.body12, label %while.end12
while.body12:
  %t161 = load ptr, ptr %ff.addr.3, align 8
  %t162 = load i32, ptr %bi.addr.156, align 4
  %t163 = call ptr @node-at(ptr %t161, i32 %t162)
  store ptr %t163, ptr %bf.addr.160, align 8
  store i32 0, ptr %is-tl.addr.164, align 4
  %t165 = load ptr, ptr %bf.addr.160, align 8
  %t166 = icmp ne ptr %t165, null
  store i1 %t166, ptr %and.val14, align 1
  br i1 %t166, label %and.rhs14, label %and.end14
and.rhs14:
  %t167 = load ptr, ptr %bf.addr.160, align 8
  %t168 = getelementptr inbounds %Node, ptr %t167, i32 0, i32 0
  %t169 = load i32, ptr %t168, align 4
  %t170 = icmp eq i32 %t169, 3
  store i1 %t170, ptr %and.val15, align 1
  br i1 %t170, label %and.rhs15, label %and.end15
and.rhs15:
  %t171 = load ptr, ptr %bf.addr.160, align 8
  %t172 = call i32 @node-len(ptr %t171)
  %t173 = icmp ne i32 %t172, 0
  store i1 %t173, ptr %and.val16, align 1
  br i1 %t173, label %and.rhs16, label %and.end16
and.rhs16:
  %t174 = load ptr, ptr %bf.addr.160, align 8
  %t175 = call ptr @node-at(ptr %t174, i32 0)
  %t176 = getelementptr inbounds %Node, ptr %t175, i32 0, i32 0
  %t177 = load i32, ptr %t176, align 4
  %t178 = icmp eq i32 %t177, 2
  store i1 %t178, ptr %and.val16, align 1
  br label %and.end16
and.end16:
  %t179 = load i1, ptr %and.val16, align 1
  store i1 %t179, ptr %and.val15, align 1
  br label %and.end15
and.end15:
  %t180 = load i1, ptr %and.val15, align 1
  store i1 %t180, ptr %and.val14, align 1
  br label %and.end14
and.end14:
  %t181 = load i1, ptr %and.val14, align 1
  br i1 %t181, label %cond.then13.0, label %cond.end13
cond.then13.0:
  %t183 = load ptr, ptr %bf.addr.160, align 8
  %t184 = call ptr @node-at(ptr %t183, i32 0)
  %t185 = getelementptr inbounds %Node, ptr %t184, i32 0, i32 3
  %t186 = load ptr, ptr %t185, align 8
  store ptr %t186, ptr %bh.addr.182, align 8
  %t187 = load ptr, ptr %bh.addr.182, align 8
  %t188 = getelementptr inbounds [10 x i8], ptr @.str.481, i64 0, i64 0
  %t189 = call i32 @strcmp(ptr %t187, ptr %t188)
  %t190 = icmp eq i32 %t189, 0
  br i1 %t190, label %cond.then17.0, label %cond.end17
cond.then17.0:
  store i32 1, ptr %is-tl.addr.164, align 4
  %t191 = load ptr, ptr %ct-type.addr.24, align 8
  store ptr %t191, ptr @g-out, align 8
  %t192 = load ptr, ptr %bf.addr.160, align 8
  call void @emit-defstruct(ptr %t192)
  br label %cond.end17
cond.end17:
  %t193 = load ptr, ptr %bh.addr.182, align 8
  %t194 = getelementptr inbounds [9 x i8], ptr @.str.482, i64 0, i64 0
  %t195 = call i32 @strcmp(ptr %t193, ptr %t194)
  %t196 = icmp eq i32 %t195, 0
  br i1 %t196, label %cond.then18.0, label %cond.end18
cond.then18.0:
  store i32 1, ptr %is-tl.addr.164, align 4
  %t197 = load ptr, ptr %bf.addr.160, align 8
  call void @emit-defconst(ptr %t197)
  br label %cond.end18
cond.end18:
  %t198 = load ptr, ptr %bh.addr.182, align 8
  %t199 = getelementptr inbounds [8 x i8], ptr @.str.483, i64 0, i64 0
  %t200 = call i32 @strcmp(ptr %t198, ptr %t199)
  %t201 = icmp eq i32 %t200, 0
  br i1 %t201, label %cond.then19.0, label %cond.end19
cond.then19.0:
  store i32 1, ptr %is-tl.addr.164, align 4
  %t202 = load ptr, ptr %bf.addr.160, align 8
  call void @emit-defenum(ptr %t202)
  br label %cond.end19
cond.end19:
  %t203 = load ptr, ptr %bh.addr.182, align 8
  %t204 = getelementptr inbounds [7 x i8], ptr @.str.484, i64 0, i64 0
  %t205 = call i32 @strcmp(ptr %t203, ptr %t204)
  %t206 = icmp eq i32 %t205, 0
  br i1 %t206, label %cond.then20.0, label %cond.end20
cond.then20.0:
  store i32 1, ptr %is-tl.addr.164, align 4
  %t207 = load ptr, ptr %ct-decl.addr.26, align 8
  store ptr %t207, ptr @g-out, align 8
  %t208 = load ptr, ptr %bf.addr.160, align 8
  call void @emit-defvar(ptr %t208)
  br label %cond.end20
cond.end20:
  %t209 = load ptr, ptr %bh.addr.182, align 8
  %t210 = getelementptr inbounds [8 x i8], ptr @.str.485, i64 0, i64 0
  %t211 = call i32 @strcmp(ptr %t209, ptr %t210)
  %t212 = icmp eq i32 %t211, 0
  br i1 %t212, label %cond.then21.0, label %cond.end21
cond.then21.0:
  store i32 1, ptr %is-tl.addr.164, align 4
  %t213 = load ptr, ptr %ct-decl.addr.26, align 8
  store ptr %t213, ptr @g-out, align 8
  %t214 = load ptr, ptr %bf.addr.160, align 8
  call void @emit-include(ptr %t214)
  br label %cond.end21
cond.end21:
  %t215 = load ptr, ptr %bh.addr.182, align 8
  %t216 = getelementptr inbounds [7 x i8], ptr @.str.486, i64 0, i64 0
  %t217 = call i32 @strcmp(ptr %t215, ptr %t216)
  %t218 = icmp eq i32 %t217, 0
  br i1 %t218, label %cond.then22.0, label %cond.end22
cond.then22.0:
  store i32 1, ptr %is-tl.addr.164, align 4
  %t219 = load ptr, ptr %ct-decl.addr.26, align 8
  store ptr %t219, ptr @g-out, align 8
  %t220 = load ptr, ptr %bf.addr.160, align 8
  call void @emit-extern(ptr %t220)
  br label %cond.end22
cond.end22:
  %t221 = load ptr, ptr %bh.addr.182, align 8
  %t222 = getelementptr inbounds [5 x i8], ptr @.str.487, i64 0, i64 0
  %t223 = call i32 @strcmp(ptr %t221, ptr %t222)
  %t224 = icmp eq i32 %t223, 0
  br i1 %t224, label %cond.then23.0, label %cond.end23
cond.then23.0:
  store i32 1, ptr %is-tl.addr.164, align 4
  %t225 = load ptr, ptr %ct-def.addr.28, align 8
  store ptr %t225, ptr @g-out, align 8
  %t226 = load ptr, ptr %bf.addr.160, align 8
  call void @emit-defn(ptr %t226)
  br label %cond.end23
cond.end23:
  br label %cond.end13
cond.end13:
  %t227 = load i32, ptr %is-tl.addr.164, align 4
  %t228 = icmp eq i32 %t227, 0
  store i1 %t228, ptr %and.val25, align 1
  br i1 %t228, label %and.rhs25, label %and.end25
and.rhs25:
  %t229 = load i32, ptr %nexpr.addr.155, align 4
  %t230 = icmp slt i32 %t229, 256
  store i1 %t230, ptr %and.val25, align 1
  br label %and.end25
and.end25:
  %t231 = load i1, ptr %and.val25, align 1
  br i1 %t231, label %cond.then24.0, label %cond.end24
cond.then24.0:
  %t232 = load ptr, ptr %expr-forms.addr.150, align 8
  %t233 = load i32, ptr %nexpr.addr.155, align 4
  %t234 = sext i32 %t233 to i64
  %t235 = load ptr, ptr %bf.addr.160, align 8
  %t236 = getelementptr inbounds ptr, ptr %t232, i64 %t234
  store ptr %t235, ptr %t236, align 8
  %t237 = load i32, ptr %nexpr.addr.155, align 4
  %t238 = add nsw i32 %t237, 1
  store i32 %t238, ptr %nexpr.addr.155, align 4
  br label %cond.end24
cond.end24:
  %t239 = load i32, ptr %bi.addr.156, align 4
  %t240 = add nsw i32 %t239, 1
  store i32 %t240, ptr %bi.addr.156, align 4
  br label %while.cond12
while.end12:
  %t242 = getelementptr inbounds [24 x i8], ptr @.str.488, i64 0, i64 0
  %t243 = load i32, ptr @g-ct-id, align 4
  %t244 = sext i32 %t243 to i64
  %t245 = call ptr @fmt-i64(ptr %t242, i64 %t244)
  store ptr %t245, ptr %ct-sym.addr.241, align 8
  %t246 = load i32, ptr @g-ct-id, align 4
  %t247 = add nsw i32 %t246, 1
  store i32 %t247, ptr @g-ct-id, align 4
  %t248 = load ptr, ptr %ct-def.addr.28, align 8
  store ptr %t248, ptr @g-out, align 8
  call void @reset-function-state()
  %t250 = load ptr, ptr @g-globals, align 8
  %t251 = call ptr @scope-new(ptr %t250)
  store ptr %t251, ptr %fn-scope.addr.249, align 8
  store i32 0, ptr %ei.addr.252, align 4
  br label %while.cond26
while.cond26:
  %t253 = load i32, ptr %ei.addr.252, align 4
  %t254 = load i32, ptr %nexpr.addr.155, align 4
  %t255 = icmp slt i32 %t253, %t254
  br i1 %t255, label %while.body26, label %while.end26
while.body26:
  %t256 = load ptr, ptr %expr-forms.addr.150, align 8
  %t257 = load i32, ptr %ei.addr.252, align 4
  %t258 = sext i32 %t257 to i64
  %t259 = getelementptr inbounds ptr, ptr %t256, i64 %t258
  %t260 = load ptr, ptr %t259, align 8
  %t261 = load ptr, ptr %fn-scope.addr.249, align 8
  %t262 = call ptr @emit-node(ptr %t260, ptr %t261)
  %t263 = load i32, ptr %ei.addr.252, align 4
  %t264 = add nsw i32 %t263, 1
  store i32 %t264, ptr %ei.addr.252, align 4
  br label %while.cond26
while.end26:
  %t265 = load i32, ptr @g-block-term, align 4
  %t266 = icmp eq i32 %t265, 0
  br i1 %t266, label %cond.then27.0, label %cond.end27
cond.then27.0:
  %t267 = load ptr, ptr @g-body-stream, align 8
  %t268 = getelementptr inbounds [12 x i8], ptr @.str.489, i64 0, i64 0
  %t269 = call i32 (ptr, ptr, ...) @fprintf(ptr %t267, ptr %t268)
  br label %cond.end27
cond.end27:
  %t270 = load ptr, ptr @g-entry-stream, align 8
  %t271 = call i32 @fclose(ptr %t270)
  %t272 = load ptr, ptr @g-body-stream, align 8
  %t273 = call i32 @fclose(ptr %t272)
  %t274 = load ptr, ptr %ct-def.addr.28, align 8
  %t275 = getelementptr inbounds [21 x i8], ptr @.str.490, i64 0, i64 0
  %t276 = load ptr, ptr %ct-sym.addr.241, align 8
  %t277 = call i32 (ptr, ptr, ...) @fprintf(ptr %t274, ptr %t275, ptr %t276)
  %t278 = load ptr, ptr %ct-def.addr.28, align 8
  %t279 = getelementptr inbounds [8 x i8], ptr @.str.491, i64 0, i64 0
  %t280 = call i32 (ptr, ptr, ...) @fprintf(ptr %t278, ptr %t279)
  %t281 = load ptr, ptr @g-entry-bufp, align 8
  %t282 = icmp ne ptr %t281, null
  store i1 %t282, ptr %and.val29, align 1
  br i1 %t282, label %and.rhs29, label %and.end29
and.rhs29:
  %t283 = load ptr, ptr @g-entry-bufp, align 8
  %t284 = sext i32 0 to i64
  %t285 = call i32 @char-at(ptr %t283, i64 %t284)
  %t286 = icmp ne i32 %t285, 0
  store i1 %t286, ptr %and.val29, align 1
  br label %and.end29
and.end29:
  %t287 = load i1, ptr %and.val29, align 1
  br i1 %t287, label %cond.then28.0, label %cond.end28
cond.then28.0:
  %t288 = load ptr, ptr @g-entry-bufp, align 8
  %t289 = load ptr, ptr %ct-def.addr.28, align 8
  %t290 = call i32 @fputs(ptr %t288, ptr %t289)
  br label %cond.end28
cond.end28:
  %t291 = load ptr, ptr @g-body-bufp, align 8
  %t292 = icmp ne ptr %t291, null
  store i1 %t292, ptr %and.val31, align 1
  br i1 %t292, label %and.rhs31, label %and.end31
and.rhs31:
  %t293 = load ptr, ptr @g-body-bufp, align 8
  %t294 = sext i32 0 to i64
  %t295 = call i32 @char-at(ptr %t293, i64 %t294)
  %t296 = icmp ne i32 %t295, 0
  store i1 %t296, ptr %and.val31, align 1
  br label %and.end31
and.end31:
  %t297 = load i1, ptr %and.val31, align 1
  br i1 %t297, label %cond.then30.0, label %cond.end30
cond.then30.0:
  %t298 = load ptr, ptr @g-body-bufp, align 8
  %t299 = load ptr, ptr %ct-def.addr.28, align 8
  %t300 = call i32 @fputs(ptr %t298, ptr %t299)
  br label %cond.end30
cond.end30:
  %t301 = load ptr, ptr %ct-def.addr.28, align 8
  %t302 = getelementptr inbounds [4 x i8], ptr @.str.492, i64 0, i64 0
  %t303 = call i32 (ptr, ptr, ...) @fprintf(ptr %t301, ptr %t302)
  %t304 = load ptr, ptr @g-entry-bufp, align 8
  call void @free(ptr %t304)
  %t305 = load ptr, ptr @g-body-bufp, align 8
  call void @free(ptr %t305)
  store ptr null, ptr @g-entry-bufp, align 8
  store ptr null, ptr @g-body-bufp, align 8
  %t307 = load i32, ptr @g-qq-used, align 4
  store i32 %t307, ptr %ct-qq.addr.306, align 4
  %t308 = load ptr, ptr %saved-g-out.addr.30, align 8
  store ptr %t308, ptr @g-out, align 8
  %t309 = load ptr, ptr %saved-decl-out.addr.32, align 8
  store ptr %t309, ptr @g-decl-out, align 8
  %t310 = load i32, ptr %saved-qq-used.addr.34, align 4
  store i32 %t310, ptr @g-qq-used, align 4
  %t311 = load i32, ptr %ct-qq.addr.306, align 4
  %t312 = icmp ne i32 %t311, 0
  br i1 %t312, label %cond.then32.0, label %cond.end32
cond.then32.0:
  %t313 = load ptr, ptr %ct-decl.addr.26, align 8
  %t314 = getelementptr inbounds [26 x i8], ptr @.str.493, i64 0, i64 0
  %t315 = call i32 (ptr, ptr, ...) @fprintf(ptr %t313, ptr %t314)
  %t316 = load ptr, ptr %ct-def.addr.28, align 8
  %t317 = getelementptr inbounds [48 x i8], ptr @.str.494, i64 0, i64 0
  %t318 = call i32 (ptr, ptr, ...) @fprintf(ptr %t316, ptr %t317)
  %t319 = load ptr, ptr %ct-def.addr.28, align 8
  %t320 = getelementptr inbounds [34 x i8], ptr @.str.495, i64 0, i64 0
  %t321 = call i32 (ptr, ptr, ...) @fprintf(ptr %t319, ptr %t320)
  %t322 = load ptr, ptr %ct-def.addr.28, align 8
  %t323 = getelementptr inbounds [89 x i8], ptr @.str.496, i64 0, i64 0
  %t324 = call i32 (ptr, ptr, ...) @fprintf(ptr %t322, ptr %t323)
  %t325 = load ptr, ptr %ct-def.addr.28, align 8
  %t326 = getelementptr inbounds [34 x i8], ptr @.str.497, i64 0, i64 0
  %t327 = call i32 (ptr, ptr, ...) @fprintf(ptr %t325, ptr %t326)
  %t328 = load ptr, ptr %ct-def.addr.28, align 8
  %t329 = getelementptr inbounds [89 x i8], ptr @.str.498, i64 0, i64 0
  %t330 = call i32 (ptr, ptr, ...) @fprintf(ptr %t328, ptr %t329)
  %t331 = load ptr, ptr %ct-def.addr.28, align 8
  %t332 = getelementptr inbounds [36 x i8], ptr @.str.499, i64 0, i64 0
  %t333 = call i32 (ptr, ptr, ...) @fprintf(ptr %t331, ptr %t332)
  %t334 = load ptr, ptr %ct-def.addr.28, align 8
  %t335 = getelementptr inbounds [89 x i8], ptr @.str.500, i64 0, i64 0
  %t336 = call i32 (ptr, ptr, ...) @fprintf(ptr %t334, ptr %t335)
  %t337 = load ptr, ptr %ct-def.addr.28, align 8
  %t338 = getelementptr inbounds [36 x i8], ptr @.str.501, i64 0, i64 0
  %t339 = call i32 (ptr, ptr, ...) @fprintf(ptr %t337, ptr %t338)
  %t340 = load ptr, ptr %ct-def.addr.28, align 8
  %t341 = getelementptr inbounds [15 x i8], ptr @.str.502, i64 0, i64 0
  %t342 = call i32 (ptr, ptr, ...) @fprintf(ptr %t340, ptr %t341)
  %t343 = load ptr, ptr %ct-def.addr.28, align 8
  %t344 = getelementptr inbounds [4 x i8], ptr @.str.503, i64 0, i64 0
  %t345 = call i32 (ptr, ptr, ...) @fprintf(ptr %t343, ptr %t344)
  %t346 = load ptr, ptr %ct-def.addr.28, align 8
  %t347 = getelementptr inbounds [50 x i8], ptr @.str.504, i64 0, i64 0
  %t348 = call i32 (ptr, ptr, ...) @fprintf(ptr %t346, ptr %t347)
  %t349 = load ptr, ptr %ct-def.addr.28, align 8
  %t350 = getelementptr inbounds [8 x i8], ptr @.str.505, i64 0, i64 0
  %t351 = call i32 (ptr, ptr, ...) @fprintf(ptr %t349, ptr %t350)
  %t352 = load ptr, ptr %ct-def.addr.28, align 8
  %t353 = getelementptr inbounds [31 x i8], ptr @.str.506, i64 0, i64 0
  %t354 = call i32 (ptr, ptr, ...) @fprintf(ptr %t352, ptr %t353)
  %t355 = load ptr, ptr %ct-def.addr.28, align 8
  %t356 = getelementptr inbounds [39 x i8], ptr @.str.507, i64 0, i64 0
  %t357 = call i32 (ptr, ptr, ...) @fprintf(ptr %t355, ptr %t356)
  %t358 = load ptr, ptr %ct-def.addr.28, align 8
  %t359 = getelementptr inbounds [6 x i8], ptr @.str.508, i64 0, i64 0
  %t360 = call i32 (ptr, ptr, ...) @fprintf(ptr %t358, ptr %t359)
  %t361 = load ptr, ptr %ct-def.addr.28, align 8
  %t362 = getelementptr inbounds [15 x i8], ptr @.str.509, i64 0, i64 0
  %t363 = call i32 (ptr, ptr, ...) @fprintf(ptr %t361, ptr %t362)
  %t364 = load ptr, ptr %ct-def.addr.28, align 8
  %t365 = getelementptr inbounds [6 x i8], ptr @.str.510, i64 0, i64 0
  %t366 = call i32 (ptr, ptr, ...) @fprintf(ptr %t364, ptr %t365)
  %t367 = load ptr, ptr %ct-def.addr.28, align 8
  %t368 = getelementptr inbounds [89 x i8], ptr @.str.511, i64 0, i64 0
  %t369 = call i32 (ptr, ptr, ...) @fprintf(ptr %t367, ptr %t368)
  %t370 = load ptr, ptr %ct-def.addr.28, align 8
  %t371 = getelementptr inbounds [39 x i8], ptr @.str.512, i64 0, i64 0
  %t372 = call i32 (ptr, ptr, ...) @fprintf(ptr %t370, ptr %t371)
  %t373 = load ptr, ptr %ct-def.addr.28, align 8
  %t374 = getelementptr inbounds [89 x i8], ptr @.str.513, i64 0, i64 0
  %t375 = call i32 (ptr, ptr, ...) @fprintf(ptr %t373, ptr %t374)
  %t376 = load ptr, ptr %ct-def.addr.28, align 8
  %t377 = getelementptr inbounds [39 x i8], ptr @.str.514, i64 0, i64 0
  %t378 = call i32 (ptr, ptr, ...) @fprintf(ptr %t376, ptr %t377)
  %t379 = load ptr, ptr %ct-def.addr.28, align 8
  %t380 = getelementptr inbounds [51 x i8], ptr @.str.515, i64 0, i64 0
  %t381 = call i32 (ptr, ptr, ...) @fprintf(ptr %t379, ptr %t380)
  %t382 = load ptr, ptr %ct-def.addr.28, align 8
  %t383 = getelementptr inbounds [49 x i8], ptr @.str.516, i64 0, i64 0
  %t384 = call i32 (ptr, ptr, ...) @fprintf(ptr %t382, ptr %t383)
  %t385 = load ptr, ptr %ct-def.addr.28, align 8
  %t386 = getelementptr inbounds [15 x i8], ptr @.str.517, i64 0, i64 0
  %t387 = call i32 (ptr, ptr, ...) @fprintf(ptr %t385, ptr %t386)
  %t388 = load ptr, ptr %ct-def.addr.28, align 8
  %t389 = getelementptr inbounds [4 x i8], ptr @.str.518, i64 0, i64 0
  %t390 = call i32 (ptr, ptr, ...) @fprintf(ptr %t388, ptr %t389)
  br label %cond.end32
cond.end32:
  %t391 = load ptr, ptr %ct-type.addr.24, align 8
  %t392 = call i32 @fclose(ptr %t391)
  %t393 = load ptr, ptr %ct-decl.addr.26, align 8
  %t394 = call i32 @fclose(ptr %t393)
  %t395 = load ptr, ptr %ct-def.addr.28, align 8
  %t396 = call i32 @fclose(ptr %t395)
  store ptr null, ptr %ir-bufp.addr.397, align 8
  %t399 = sext i32 0 to i64
  store i64 %t399, ptr %ir-sizep.addr.398, align 8
  %t401 = call ptr @open_memstream(ptr %ir-bufp.addr.397, ptr %ir-sizep.addr.398)
  store ptr %t401, ptr %irs.addr.400, align 8
  %t402 = load ptr, ptr %irs.addr.400, align 8
  %t403 = getelementptr inbounds [31 x i8], ptr @.str.519, i64 0, i64 0
  %t404 = call i32 (ptr, ptr, ...) @fprintf(ptr %t402, ptr %t403)
  %t405 = load ptr, ptr %irs.addr.400, align 8
  %t406 = getelementptr inbounds [40 x i8], ptr @.str.520, i64 0, i64 0
  %t407 = call i32 (ptr, ptr, ...) @fprintf(ptr %t405, ptr %t406)
  %t408 = load i32, ptr @g-interactive, align 4
  %t409 = icmp ne i32 %t408, 0
  br i1 %t409, label %cond.then33.0, label %cond.end33
cond.then33.0:
  %t410 = load ptr, ptr @g-repl-preamble, align 8
  %t411 = call i32 @fflush(ptr %t410)
  %t412 = load ptr, ptr @g-repl-preamble-bufp, align 8
  %t413 = icmp ne ptr %t412, null
  store i1 %t413, ptr %and.val35, align 1
  br i1 %t413, label %and.rhs35, label %and.end35
and.rhs35:
  %t414 = load ptr, ptr @g-repl-preamble-bufp, align 8
  %t415 = sext i32 0 to i64
  %t416 = call i32 @char-at(ptr %t414, i64 %t415)
  %t417 = icmp ne i32 %t416, 0
  store i1 %t417, ptr %and.val35, align 1
  br label %and.end35
and.end35:
  %t418 = load i1, ptr %and.val35, align 1
  br i1 %t418, label %cond.then34.0, label %cond.end34
cond.then34.0:
  %t419 = load ptr, ptr @g-repl-preamble-bufp, align 8
  %t420 = load ptr, ptr %irs.addr.400, align 8
  %t421 = call i32 @fputs(ptr %t419, ptr %t420)
  br label %cond.end34
cond.end34:
  br label %cond.end33
cond.end33:
  %t422 = load ptr, ptr @g-type-bufp, align 8
  %t423 = icmp ne ptr %t422, null
  store i1 %t423, ptr %and.val37, align 1
  br i1 %t423, label %and.rhs37, label %and.end37
and.rhs37:
  %t424 = load ptr, ptr @g-type-bufp, align 8
  %t425 = sext i32 0 to i64
  %t426 = call i32 @char-at(ptr %t424, i64 %t425)
  %t427 = icmp ne i32 %t426, 0
  store i1 %t427, ptr %and.val37, align 1
  br label %and.end37
and.end37:
  %t428 = load i1, ptr %and.val37, align 1
  br i1 %t428, label %cond.then36.0, label %cond.end36
cond.then36.0:
  %t429 = load ptr, ptr @g-type-bufp, align 8
  %t430 = load ptr, ptr %irs.addr.400, align 8
  %t431 = call i32 @fputs(ptr %t429, ptr %t430)
  br label %cond.end36
cond.end36:
  %t432 = load ptr, ptr %ct-type-bufp.addr.15, align 8
  %t433 = icmp ne ptr %t432, null
  store i1 %t433, ptr %and.val39, align 1
  br i1 %t433, label %and.rhs39, label %and.end39
and.rhs39:
  %t434 = load ptr, ptr %ct-type-bufp.addr.15, align 8
  %t435 = sext i32 0 to i64
  %t436 = call i32 @char-at(ptr %t434, i64 %t435)
  %t437 = icmp ne i32 %t436, 0
  store i1 %t437, ptr %and.val39, align 1
  br label %and.end39
and.end39:
  %t438 = load i1, ptr %and.val39, align 1
  br i1 %t438, label %cond.then38.0, label %cond.end38
cond.then38.0:
  %t439 = load ptr, ptr %ct-type-bufp.addr.15, align 8
  %t440 = load ptr, ptr %irs.addr.400, align 8
  %t441 = call i32 @fputs(ptr %t439, ptr %t440)
  br label %cond.end38
cond.end38:
  %t442 = load ptr, ptr %irs.addr.400, align 8
  call void @emit-string-table(ptr %t442)
  %t443 = load ptr, ptr @g-decl-bufp, align 8
  %t444 = icmp ne ptr %t443, null
  store i1 %t444, ptr %and.val41, align 1
  br i1 %t444, label %and.rhs41, label %and.end41
and.rhs41:
  %t445 = load ptr, ptr @g-decl-bufp, align 8
  %t446 = sext i32 0 to i64
  %t447 = call i32 @char-at(ptr %t445, i64 %t446)
  %t448 = icmp ne i32 %t447, 0
  store i1 %t448, ptr %and.val41, align 1
  br label %and.end41
and.end41:
  %t449 = load i1, ptr %and.val41, align 1
  br i1 %t449, label %cond.then40.0, label %cond.end40
cond.then40.0:
  %t450 = load ptr, ptr @g-decl-bufp, align 8
  %t451 = load ptr, ptr %irs.addr.400, align 8
  %t452 = call i32 @fputs(ptr %t450, ptr %t451)
  br label %cond.end40
cond.end40:
  %t453 = load ptr, ptr %ct-decl-bufp.addr.18, align 8
  %t454 = icmp ne ptr %t453, null
  store i1 %t454, ptr %and.val43, align 1
  br i1 %t454, label %and.rhs43, label %and.end43
and.rhs43:
  %t455 = load ptr, ptr %ct-decl-bufp.addr.18, align 8
  %t456 = sext i32 0 to i64
  %t457 = call i32 @char-at(ptr %t455, i64 %t456)
  %t458 = icmp ne i32 %t457, 0
  store i1 %t458, ptr %and.val43, align 1
  br label %and.end43
and.end43:
  %t459 = load i1, ptr %and.val43, align 1
  br i1 %t459, label %cond.then42.0, label %cond.end42
cond.then42.0:
  %t460 = load ptr, ptr %ct-decl-bufp.addr.18, align 8
  %t461 = load ptr, ptr %irs.addr.400, align 8
  %t462 = call i32 @fputs(ptr %t460, ptr %t461)
  br label %cond.end42
cond.end42:
  %t463 = load ptr, ptr %ct-def-bufp.addr.21, align 8
  %t464 = icmp ne ptr %t463, null
  store i1 %t464, ptr %and.val45, align 1
  br i1 %t464, label %and.rhs45, label %and.end45
and.rhs45:
  %t465 = load ptr, ptr %ct-def-bufp.addr.21, align 8
  %t466 = sext i32 0 to i64
  %t467 = call i32 @char-at(ptr %t465, i64 %t466)
  %t468 = icmp ne i32 %t467, 0
  store i1 %t468, ptr %and.val45, align 1
  br label %and.end45
and.end45:
  %t469 = load i1, ptr %and.val45, align 1
  br i1 %t469, label %cond.then44.0, label %cond.end44
cond.then44.0:
  %t470 = load ptr, ptr %ct-def-bufp.addr.21, align 8
  %t471 = load ptr, ptr %irs.addr.400, align 8
  %t472 = call i32 @fputs(ptr %t470, ptr %t471)
  br label %cond.end44
cond.end44:
  %t473 = load ptr, ptr %irs.addr.400, align 8
  %t474 = call i32 @fclose(ptr %t473)
  %t475 = load ptr, ptr %ir-bufp.addr.397, align 8
  %t476 = load ptr, ptr %ff.addr.3, align 8
  %t477 = getelementptr inbounds %Node, ptr %t476, i32 0, i32 1
  %t478 = load i32, ptr %t477, align 4
  call void @jit-add-module(ptr %t475, i32 %t478)
  %t479 = load ptr, ptr %ff.addr.3, align 8
  %t480 = getelementptr inbounds %Node, ptr %t479, i32 0, i32 1
  %t481 = load i32, ptr %t480, align 4
  %t482 = load ptr, ptr %ct-sym.addr.241, align 8
  call void @jit-call-ct-main-sym(i32 %t481, ptr %t482)
  %t483 = load ptr, ptr %ct-type-bufp.addr.15, align 8
  call void @free(ptr %t483)
  %t484 = load ptr, ptr %ct-decl-bufp.addr.18, align 8
  call void @free(ptr %t484)
  %t485 = load ptr, ptr %ct-def-bufp.addr.21, align 8
  call void @free(ptr %t485)
  %t486 = load ptr, ptr %ir-bufp.addr.397, align 8
  call void @free(ptr %t486)
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
  %and.val24 = alloca i1, align 1
  %and.val26 = alloca i1, align 1
  %and.val28 = alloca i1, align 1
  %and.val30 = alloca i1, align 1
  %and.val32 = alloca i1, align 1
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
  %t8 = getelementptr inbounds [41 x i8], ptr @.str.521, i64 0, i64 0
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
  %t22 = getelementptr inbounds [30 x i8], ptr @.str.522, i64 0, i64 0
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
  %t29 = getelementptr inbounds [32 x i8], ptr @.str.523, i64 0, i64 0
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
  %t38 = getelementptr inbounds [11 x i8], ptr @.str.524, i64 0, i64 0
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
  %t56 = getelementptr inbounds [6 x i8], ptr @.str.525, i64 0, i64 0
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
  %t66 = getelementptr inbounds [45 x i8], ptr @.str.526, i64 0, i64 0
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
  %t95 = getelementptr inbounds [33 x i8], ptr @.str.527, i64 0, i64 0
  call void @die-at(i32 %t94, ptr %t95)
  br label %cond.end8
cond.end8:
  %t96 = load ptr, ptr %p.addr.84, align 8
  %t97 = getelementptr inbounds %Node, ptr %t96, i32 0, i32 3
  %t98 = load ptr, ptr %t97, align 8
  %t99 = getelementptr inbounds [6 x i8], ptr @.str.528, i64 0, i64 0
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
  %t118 = getelementptr inbounds [27 x i8], ptr @.str.529, i64 0, i64 0
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
  %t164 = getelementptr inbounds [39 x i8], ptr @.str.530, i64 0, i64 0
  %t165 = call i32 (ptr, ptr, ...) @fprintf(ptr %t163, ptr %t164)
  %t166 = load ptr, ptr @g-entry-stream, align 8
  %t167 = getelementptr inbounds [54 x i8], ptr @.str.531, i64 0, i64 0
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
  %t180 = getelementptr inbounds [35 x i8], ptr @.str.532, i64 0, i64 0
  %t181 = load ptr, ptr %pname.addr.173, align 8
  %t182 = call i32 (ptr, ptr, ...) @fprintf(ptr %t179, ptr %t180, ptr %t181)
  %t183 = load ptr, ptr @g-entry-stream, align 8
  %t184 = getelementptr inbounds [51 x i8], ptr @.str.533, i64 0, i64 0
  %t185 = load i32, ptr %ei.addr.169, align 4
  %t186 = call i32 (ptr, ptr, ...) @fprintf(ptr %t183, ptr %t184, i32 %t185)
  %t187 = load ptr, ptr @g-entry-stream, align 8
  %t188 = getelementptr inbounds [54 x i8], ptr @.str.534, i64 0, i64 0
  %t189 = load i32, ptr %ei.addr.169, align 4
  %t190 = load i32, ptr %ei.addr.169, align 4
  %t191 = load i32, ptr %ei.addr.169, align 4
  %t192 = call i32 (ptr, ptr, ...) @fprintf(ptr %t187, ptr %t188, i32 %t189, i32 %t190, i32 %t191)
  %t193 = load ptr, ptr @g-entry-stream, align 8
  %t194 = getelementptr inbounds [46 x i8], ptr @.str.535, i64 0, i64 0
  %t195 = load i32, ptr %ei.addr.169, align 4
  %t196 = load i32, ptr %ei.addr.169, align 4
  %t197 = call i32 (ptr, ptr, ...) @fprintf(ptr %t193, ptr %t194, i32 %t195, i32 %t196)
  %t198 = load ptr, ptr @g-entry-stream, align 8
  %t199 = getelementptr inbounds [46 x i8], ptr @.str.536, i64 0, i64 0
  %t200 = load i32, ptr %ei.addr.169, align 4
  %t201 = load ptr, ptr %pname.addr.173, align 8
  %t202 = call i32 (ptr, ptr, ...) @fprintf(ptr %t198, ptr %t199, i32 %t200, ptr %t201)
  %t203 = load ptr, ptr %fn-scope.addr.160, align 8
  %t204 = load ptr, ptr %pname.addr.173, align 8
  %t205 = load ptr, ptr @ty-ptr, align 8
  %t206 = getelementptr inbounds [10 x i8], ptr @.str.537, i64 0, i64 0
  %t207 = load ptr, ptr %pname.addr.173, align 8
  %t208 = call ptr @fmt-s(ptr %t206, ptr %t207)
  %t209 = call ptr @scope-define(ptr %t203, ptr %t204, ptr %t205, ptr %t208, i32 1)
  %t210 = load i32, ptr %ei.addr.169, align 4
  %t211 = add nsw i32 %t210, 1
  store i32 %t211, ptr %ei.addr.169, align 4
  br label %while.cond11
while.end11:
  %t213 = getelementptr inbounds [5 x i8], ptr @.str.538, i64 0, i64 0
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
  %t236 = icmp eq i32 %t235, 10
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
  %t245 = getelementptr inbounds [14 x i8], ptr @.str.539, i64 0, i64 0
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
  %t258 = getelementptr inbounds [36 x i8], ptr @.str.540, i64 0, i64 0
  %t259 = load ptr, ptr %jit-name.addr.37, align 8
  %t260 = call i32 (ptr, ptr, ...) @fprintf(ptr %t257, ptr %t258, ptr %t259)
  %t261 = load ptr, ptr %ct-def.addr.150, align 8
  %t262 = getelementptr inbounds [8 x i8], ptr @.str.541, i64 0, i64 0
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
  %t285 = getelementptr inbounds [4 x i8], ptr @.str.542, i64 0, i64 0
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
  %t294 = getelementptr inbounds [26 x i8], ptr @.str.543, i64 0, i64 0
  %t295 = call i32 (ptr, ptr, ...) @fprintf(ptr %t293, ptr %t294)
  br label %cond.end21
cond.end21:
  %t296 = load ptr, ptr %ct-def.addr.150, align 8
  %t297 = getelementptr inbounds [48 x i8], ptr @.str.544, i64 0, i64 0
  %t298 = call i32 (ptr, ptr, ...) @fprintf(ptr %t296, ptr %t297)
  %t299 = load ptr, ptr %ct-def.addr.150, align 8
  %t300 = getelementptr inbounds [34 x i8], ptr @.str.545, i64 0, i64 0
  %t301 = call i32 (ptr, ptr, ...) @fprintf(ptr %t299, ptr %t300)
  %t302 = load ptr, ptr %ct-def.addr.150, align 8
  %t303 = getelementptr inbounds [89 x i8], ptr @.str.546, i64 0, i64 0
  %t304 = call i32 (ptr, ptr, ...) @fprintf(ptr %t302, ptr %t303)
  %t305 = load ptr, ptr %ct-def.addr.150, align 8
  %t306 = getelementptr inbounds [34 x i8], ptr @.str.547, i64 0, i64 0
  %t307 = call i32 (ptr, ptr, ...) @fprintf(ptr %t305, ptr %t306)
  %t308 = load ptr, ptr %ct-def.addr.150, align 8
  %t309 = getelementptr inbounds [89 x i8], ptr @.str.548, i64 0, i64 0
  %t310 = call i32 (ptr, ptr, ...) @fprintf(ptr %t308, ptr %t309)
  %t311 = load ptr, ptr %ct-def.addr.150, align 8
  %t312 = getelementptr inbounds [34 x i8], ptr @.str.549, i64 0, i64 0
  %t313 = call i32 (ptr, ptr, ...) @fprintf(ptr %t311, ptr %t312)
  %t314 = load ptr, ptr %ct-def.addr.150, align 8
  %t315 = getelementptr inbounds [89 x i8], ptr @.str.550, i64 0, i64 0
  %t316 = call i32 (ptr, ptr, ...) @fprintf(ptr %t314, ptr %t315)
  %t317 = load ptr, ptr %ct-def.addr.150, align 8
  %t318 = getelementptr inbounds [34 x i8], ptr @.str.551, i64 0, i64 0
  %t319 = call i32 (ptr, ptr, ...) @fprintf(ptr %t317, ptr %t318)
  %t320 = load ptr, ptr %ct-def.addr.150, align 8
  %t321 = getelementptr inbounds [89 x i8], ptr @.str.552, i64 0, i64 0
  %t322 = call i32 (ptr, ptr, ...) @fprintf(ptr %t320, ptr %t321)
  %t323 = load ptr, ptr %ct-def.addr.150, align 8
  %t324 = getelementptr inbounds [37 x i8], ptr @.str.553, i64 0, i64 0
  %t325 = call i32 (ptr, ptr, ...) @fprintf(ptr %t323, ptr %t324)
  %t326 = load ptr, ptr %ct-def.addr.150, align 8
  %t327 = getelementptr inbounds [89 x i8], ptr @.str.554, i64 0, i64 0
  %t328 = call i32 (ptr, ptr, ...) @fprintf(ptr %t326, ptr %t327)
  %t329 = load ptr, ptr %ct-def.addr.150, align 8
  %t330 = getelementptr inbounds [36 x i8], ptr @.str.555, i64 0, i64 0
  %t331 = call i32 (ptr, ptr, ...) @fprintf(ptr %t329, ptr %t330)
  %t332 = load ptr, ptr %ct-def.addr.150, align 8
  %t333 = getelementptr inbounds [89 x i8], ptr @.str.556, i64 0, i64 0
  %t334 = call i32 (ptr, ptr, ...) @fprintf(ptr %t332, ptr %t333)
  %t335 = load ptr, ptr %ct-def.addr.150, align 8
  %t336 = getelementptr inbounds [36 x i8], ptr @.str.557, i64 0, i64 0
  %t337 = call i32 (ptr, ptr, ...) @fprintf(ptr %t335, ptr %t336)
  %t338 = load ptr, ptr %ct-def.addr.150, align 8
  %t339 = getelementptr inbounds [15 x i8], ptr @.str.558, i64 0, i64 0
  %t340 = call i32 (ptr, ptr, ...) @fprintf(ptr %t338, ptr %t339)
  %t341 = load ptr, ptr %ct-def.addr.150, align 8
  %t342 = getelementptr inbounds [4 x i8], ptr @.str.559, i64 0, i64 0
  %t343 = call i32 (ptr, ptr, ...) @fprintf(ptr %t341, ptr %t342)
  %t344 = load ptr, ptr %ct-def.addr.150, align 8
  %t345 = getelementptr inbounds [50 x i8], ptr @.str.560, i64 0, i64 0
  %t346 = call i32 (ptr, ptr, ...) @fprintf(ptr %t344, ptr %t345)
  %t347 = load ptr, ptr %ct-def.addr.150, align 8
  %t348 = getelementptr inbounds [8 x i8], ptr @.str.561, i64 0, i64 0
  %t349 = call i32 (ptr, ptr, ...) @fprintf(ptr %t347, ptr %t348)
  %t350 = load ptr, ptr %ct-def.addr.150, align 8
  %t351 = getelementptr inbounds [31 x i8], ptr @.str.562, i64 0, i64 0
  %t352 = call i32 (ptr, ptr, ...) @fprintf(ptr %t350, ptr %t351)
  %t353 = load ptr, ptr %ct-def.addr.150, align 8
  %t354 = getelementptr inbounds [39 x i8], ptr @.str.563, i64 0, i64 0
  %t355 = call i32 (ptr, ptr, ...) @fprintf(ptr %t353, ptr %t354)
  %t356 = load ptr, ptr %ct-def.addr.150, align 8
  %t357 = getelementptr inbounds [6 x i8], ptr @.str.564, i64 0, i64 0
  %t358 = call i32 (ptr, ptr, ...) @fprintf(ptr %t356, ptr %t357)
  %t359 = load ptr, ptr %ct-def.addr.150, align 8
  %t360 = getelementptr inbounds [15 x i8], ptr @.str.565, i64 0, i64 0
  %t361 = call i32 (ptr, ptr, ...) @fprintf(ptr %t359, ptr %t360)
  %t362 = load ptr, ptr %ct-def.addr.150, align 8
  %t363 = getelementptr inbounds [6 x i8], ptr @.str.566, i64 0, i64 0
  %t364 = call i32 (ptr, ptr, ...) @fprintf(ptr %t362, ptr %t363)
  %t365 = load ptr, ptr %ct-def.addr.150, align 8
  %t366 = getelementptr inbounds [89 x i8], ptr @.str.567, i64 0, i64 0
  %t367 = call i32 (ptr, ptr, ...) @fprintf(ptr %t365, ptr %t366)
  %t368 = load ptr, ptr %ct-def.addr.150, align 8
  %t369 = getelementptr inbounds [39 x i8], ptr @.str.568, i64 0, i64 0
  %t370 = call i32 (ptr, ptr, ...) @fprintf(ptr %t368, ptr %t369)
  %t371 = load ptr, ptr %ct-def.addr.150, align 8
  %t372 = getelementptr inbounds [89 x i8], ptr @.str.569, i64 0, i64 0
  %t373 = call i32 (ptr, ptr, ...) @fprintf(ptr %t371, ptr %t372)
  %t374 = load ptr, ptr %ct-def.addr.150, align 8
  %t375 = getelementptr inbounds [39 x i8], ptr @.str.570, i64 0, i64 0
  %t376 = call i32 (ptr, ptr, ...) @fprintf(ptr %t374, ptr %t375)
  %t377 = load ptr, ptr %ct-def.addr.150, align 8
  %t378 = getelementptr inbounds [51 x i8], ptr @.str.571, i64 0, i64 0
  %t379 = call i32 (ptr, ptr, ...) @fprintf(ptr %t377, ptr %t378)
  %t380 = load ptr, ptr %ct-def.addr.150, align 8
  %t381 = getelementptr inbounds [49 x i8], ptr @.str.572, i64 0, i64 0
  %t382 = call i32 (ptr, ptr, ...) @fprintf(ptr %t380, ptr %t381)
  %t383 = load ptr, ptr %ct-def.addr.150, align 8
  %t384 = getelementptr inbounds [15 x i8], ptr @.str.573, i64 0, i64 0
  %t385 = call i32 (ptr, ptr, ...) @fprintf(ptr %t383, ptr %t384)
  %t386 = load ptr, ptr %ct-def.addr.150, align 8
  %t387 = getelementptr inbounds [4 x i8], ptr @.str.574, i64 0, i64 0
  %t388 = call i32 (ptr, ptr, ...) @fprintf(ptr %t386, ptr %t387)
  br label %cond.end20
cond.end20:
  %t389 = load ptr, ptr %ct-decl.addr.148, align 8
  %t390 = getelementptr inbounds [31 x i8], ptr @.str.575, i64 0, i64 0
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
  %t402 = getelementptr inbounds [30 x i8], ptr @.str.576, i64 0, i64 0
  %t403 = load ptr, ptr %macro-name.addr.30, align 8
  %t404 = call i32 (ptr, ptr, ...) @fprintf(ptr %t401, ptr %t402, ptr %t403)
  %t405 = load ptr, ptr %irs.addr.399, align 8
  %t406 = getelementptr inbounds [40 x i8], ptr @.str.577, i64 0, i64 0
  %t407 = call i32 (ptr, ptr, ...) @fprintf(ptr %t405, ptr %t406)
  %t408 = load i32, ptr @g-interactive, align 4
  %t409 = icmp ne i32 %t408, 0
  br i1 %t409, label %cond.then22.0, label %cond.end22
cond.then22.0:
  %t410 = load ptr, ptr @g-repl-preamble, align 8
  %t411 = call i32 @fflush(ptr %t410)
  %t412 = load ptr, ptr @g-repl-preamble-bufp, align 8
  %t413 = icmp ne ptr %t412, null
  store i1 %t413, ptr %and.val24, align 1
  br i1 %t413, label %and.rhs24, label %and.end24
and.rhs24:
  %t414 = load ptr, ptr @g-repl-preamble-bufp, align 8
  %t415 = sext i32 0 to i64
  %t416 = call i32 @char-at(ptr %t414, i64 %t415)
  %t417 = icmp ne i32 %t416, 0
  store i1 %t417, ptr %and.val24, align 1
  br label %and.end24
and.end24:
  %t418 = load i1, ptr %and.val24, align 1
  br i1 %t418, label %cond.then23.0, label %cond.end23
cond.then23.0:
  %t419 = load ptr, ptr @g-repl-preamble-bufp, align 8
  %t420 = load ptr, ptr %irs.addr.399, align 8
  %t421 = call i32 @fputs(ptr %t419, ptr %t420)
  br label %cond.end23
cond.end23:
  br label %cond.end22
cond.end22:
  %t422 = load ptr, ptr @g-type-bufp, align 8
  %t423 = icmp ne ptr %t422, null
  store i1 %t423, ptr %and.val26, align 1
  br i1 %t423, label %and.rhs26, label %and.end26
and.rhs26:
  %t424 = load ptr, ptr @g-type-bufp, align 8
  %t425 = sext i32 0 to i64
  %t426 = call i32 @char-at(ptr %t424, i64 %t425)
  %t427 = icmp ne i32 %t426, 0
  store i1 %t427, ptr %and.val26, align 1
  br label %and.end26
and.end26:
  %t428 = load i1, ptr %and.val26, align 1
  br i1 %t428, label %cond.then25.0, label %cond.end25
cond.then25.0:
  %t429 = load ptr, ptr @g-type-bufp, align 8
  %t430 = load ptr, ptr %irs.addr.399, align 8
  %t431 = call i32 @fputs(ptr %t429, ptr %t430)
  br label %cond.end25
cond.end25:
  %t432 = load ptr, ptr %irs.addr.399, align 8
  call void @emit-string-table(ptr %t432)
  %t433 = load ptr, ptr @g-decl-bufp, align 8
  %t434 = icmp ne ptr %t433, null
  store i1 %t434, ptr %and.val28, align 1
  br i1 %t434, label %and.rhs28, label %and.end28
and.rhs28:
  %t435 = load ptr, ptr @g-decl-bufp, align 8
  %t436 = sext i32 0 to i64
  %t437 = call i32 @char-at(ptr %t435, i64 %t436)
  %t438 = icmp ne i32 %t437, 0
  store i1 %t438, ptr %and.val28, align 1
  br label %and.end28
and.end28:
  %t439 = load i1, ptr %and.val28, align 1
  br i1 %t439, label %cond.then27.0, label %cond.end27
cond.then27.0:
  %t440 = load ptr, ptr @g-decl-bufp, align 8
  %t441 = load ptr, ptr %irs.addr.399, align 8
  %t442 = call i32 @fputs(ptr %t440, ptr %t441)
  br label %cond.end27
cond.end27:
  %t443 = load ptr, ptr %ct-decl-bufp.addr.142, align 8
  %t444 = icmp ne ptr %t443, null
  store i1 %t444, ptr %and.val30, align 1
  br i1 %t444, label %and.rhs30, label %and.end30
and.rhs30:
  %t445 = load ptr, ptr %ct-decl-bufp.addr.142, align 8
  %t446 = sext i32 0 to i64
  %t447 = call i32 @char-at(ptr %t445, i64 %t446)
  %t448 = icmp ne i32 %t447, 0
  store i1 %t448, ptr %and.val30, align 1
  br label %and.end30
and.end30:
  %t449 = load i1, ptr %and.val30, align 1
  br i1 %t449, label %cond.then29.0, label %cond.end29
cond.then29.0:
  %t450 = load ptr, ptr %ct-decl-bufp.addr.142, align 8
  %t451 = load ptr, ptr %irs.addr.399, align 8
  %t452 = call i32 @fputs(ptr %t450, ptr %t451)
  br label %cond.end29
cond.end29:
  %t453 = load ptr, ptr %ct-def-bufp.addr.145, align 8
  %t454 = icmp ne ptr %t453, null
  store i1 %t454, ptr %and.val32, align 1
  br i1 %t454, label %and.rhs32, label %and.end32
and.rhs32:
  %t455 = load ptr, ptr %ct-def-bufp.addr.145, align 8
  %t456 = sext i32 0 to i64
  %t457 = call i32 @char-at(ptr %t455, i64 %t456)
  %t458 = icmp ne i32 %t457, 0
  store i1 %t458, ptr %and.val32, align 1
  br label %and.end32
and.end32:
  %t459 = load i1, ptr %and.val32, align 1
  br i1 %t459, label %cond.then31.0, label %cond.end31
cond.then31.0:
  %t460 = load ptr, ptr %ct-def-bufp.addr.145, align 8
  %t461 = load ptr, ptr %irs.addr.399, align 8
  %t462 = call i32 @fputs(ptr %t460, ptr %t461)
  br label %cond.end31
cond.end31:
  %t463 = load ptr, ptr %irs.addr.399, align 8
  %t464 = call i32 @fclose(ptr %t463)
  %t465 = load ptr, ptr %ir-bufp.addr.396, align 8
  %t466 = load ptr, ptr %ff.addr.0, align 8
  %t467 = getelementptr inbounds %Node, ptr %t466, i32 0, i32 1
  %t468 = load i32, ptr %t467, align 4
  call void @jit-add-module(ptr %t465, i32 %t468)
  %t469 = load ptr, ptr %ct-decl-bufp.addr.142, align 8
  call void @free(ptr %t469)
  %t470 = load ptr, ptr %ct-def-bufp.addr.145, align 8
  call void @free(ptr %t470)
  %t471 = load ptr, ptr %ir-bufp.addr.396, align 8
  call void @free(ptr %t471)
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
  %t15 = getelementptr inbounds [54 x i8], ptr @.str.578, i64 0, i64 0
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
  %t46 = getelementptr inbounds [6 x i8], ptr @.str.579, i64 0, i64 0
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
  %t55 = getelementptr inbounds [15 x i8], ptr @.str.580, i64 0, i64 0
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
  %t2 = getelementptr inbounds [3 x i8], ptr @.str.581, i64 0, i64 0
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
  %t11 = getelementptr inbounds [6 x i8], ptr @.str.582, i64 0, i64 0
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
  %t18 = getelementptr inbounds [6 x i8], ptr @.str.583, i64 0, i64 0
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
  %t27 = getelementptr inbounds [7 x i8], ptr @.str.584, i64 0, i64 0
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

define ptr @desugar-symbol(ptr %sym.arg, i32 %line.arg) {
entry:
  %sym.addr = alloca ptr, align 8
  store ptr %sym.arg, ptr %sym.addr, align 8
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %s.addr.0 = alloca ptr, align 8
  %result.addr.4 = alloca ptr, align 8
  %tail.addr.5 = alloca ptr, align 8
  %start.addr.6 = alloca i64, align 8
  %i.addr.8 = alloca i64, align 8
  %slen.addr.10 = alloca i64, align 8
  %or.val2 = alloca i1, align 1
  %seg-len.addr.24 = alloca i64, align 8
  %seg.addr.28 = alloca ptr, align 8
  %n.addr.34 = alloca ptr, align 8
  %cell.addr.44 = alloca ptr, align 8
  %t1 = load ptr, ptr %sym.addr, align 8
  %t2 = getelementptr inbounds %Node, ptr %t1, i32 0, i32 3
  %t3 = load ptr, ptr %t2, align 8
  store ptr %t3, ptr %s.addr.0, align 8
  store ptr null, ptr %result.addr.4, align 8
  store ptr null, ptr %tail.addr.5, align 8
  %t7 = sext i32 0 to i64
  store i64 %t7, ptr %start.addr.6, align 8
  %t9 = sext i32 0 to i64
  store i64 %t9, ptr %i.addr.8, align 8
  %t11 = load ptr, ptr %s.addr.0, align 8
  %t12 = call i64 @strlen(ptr %t11)
  store i64 %t12, ptr %slen.addr.10, align 8
  br label %while.cond0
while.cond0:
  %t13 = load i64, ptr %i.addr.8, align 8
  %t14 = load i64, ptr %slen.addr.10, align 8
  %t15 = icmp sle i64 %t13, %t14
  br i1 %t15, label %while.body0, label %while.end0
while.body0:
  %t16 = load i64, ptr %i.addr.8, align 8
  %t17 = load i64, ptr %slen.addr.10, align 8
  %t18 = icmp eq i64 %t16, %t17
  store i1 %t18, ptr %or.val2, align 1
  br i1 %t18, label %or.end2, label %or.rhs2
or.rhs2:
  %t19 = load ptr, ptr %s.addr.0, align 8
  %t20 = load i64, ptr %i.addr.8, align 8
  %t21 = call i32 @char-at(ptr %t19, i64 %t20)
  %t22 = icmp eq i32 %t21, 58
  store i1 %t22, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t23 = load i1, ptr %or.val2, align 1
  br i1 %t23, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t25 = load i64, ptr %i.addr.8, align 8
  %t26 = load i64, ptr %start.addr.6, align 8
  %t27 = sub nsw i64 %t25, %t26
  store i64 %t27, ptr %seg-len.addr.24, align 8
  %t29 = load ptr, ptr %s.addr.0, align 8
  %t30 = load i64, ptr %start.addr.6, align 8
  %t31 = getelementptr inbounds i8, ptr %t29, i64 %t30
  %t32 = load i64, ptr %seg-len.addr.24, align 8
  %t33 = call ptr @arena-strndup(ptr %t31, i64 %t32)
  store ptr %t33, ptr %seg.addr.28, align 8
  %t35 = call ptr @alloc-node()
  store ptr %t35, ptr %n.addr.34, align 8
  %t36 = load ptr, ptr %n.addr.34, align 8
  %t37 = getelementptr inbounds %Node, ptr %t36, i32 0, i32 0
  store i32 2, ptr %t37, align 4
  %t38 = load ptr, ptr %n.addr.34, align 8
  %t39 = load i32, ptr %line.addr, align 4
  %t40 = getelementptr inbounds %Node, ptr %t38, i32 0, i32 1
  store i32 %t39, ptr %t40, align 4
  %t41 = load ptr, ptr %n.addr.34, align 8
  %t42 = load ptr, ptr %seg.addr.28, align 8
  %t43 = getelementptr inbounds %Node, ptr %t41, i32 0, i32 3
  store ptr %t42, ptr %t43, align 8
  %t45 = load ptr, ptr %n.addr.34, align 8
  %t46 = load i32, ptr %line.addr, align 4
  %t47 = call ptr @make-cell(ptr %t45, ptr null, i32 %t46)
  store ptr %t47, ptr %cell.addr.44, align 8
  %t48 = load ptr, ptr %tail.addr.5, align 8
  %t49 = icmp eq ptr %t48, null
  br i1 %t49, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t50 = load ptr, ptr %cell.addr.44, align 8
  store ptr %t50, ptr %result.addr.4, align 8
  br label %cond.end3
cond.end3:
  %t51 = load ptr, ptr %tail.addr.5, align 8
  %t52 = icmp ne ptr %t51, null
  br i1 %t52, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t53 = load ptr, ptr %tail.addr.5, align 8
  %t54 = load ptr, ptr %cell.addr.44, align 8
  %t55 = getelementptr inbounds %Node, ptr %t53, i32 0, i32 5
  store ptr %t54, ptr %t55, align 8
  br label %cond.end4
cond.end4:
  %t56 = load ptr, ptr %cell.addr.44, align 8
  store ptr %t56, ptr %tail.addr.5, align 8
  %t57 = load i64, ptr %i.addr.8, align 8
  %t58 = sext i32 1 to i64
  %t59 = add nsw i64 %t57, %t58
  store i64 %t59, ptr %start.addr.6, align 8
  br label %cond.end1
cond.end1:
  %t60 = load i64, ptr %i.addr.8, align 8
  %t61 = sext i32 1 to i64
  %t62 = add nsw i64 %t60, %t61
  store i64 %t62, ptr %i.addr.8, align 8
  br label %while.cond0
while.end0:
  %t63 = load ptr, ptr %result.addr.4, align 8
  ret ptr %t63
}

define ptr @desugar-typed(ptr %node.arg) {
entry:
  %node.addr = alloca ptr, align 8
  store ptr %node.arg, ptr %node.addr, align 8
  %n.addr.2 = alloca ptr, align 8
  %and.val2 = alloca i1, align 1
  %t0 = load ptr, ptr %node.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret ptr null
cond.end0:
  %t3 = load ptr, ptr %node.addr, align 8
  store ptr %t3, ptr %n.addr.2, align 8
  %t4 = load ptr, ptr %n.addr.2, align 8
  %t5 = getelementptr inbounds %Node, ptr %t4, i32 0, i32 0
  %t6 = load i32, ptr %t5, align 4
  %t7 = icmp eq i32 %t6, 2
  store i1 %t7, ptr %and.val2, align 1
  br i1 %t7, label %and.rhs2, label %and.end2
and.rhs2:
  %t8 = load ptr, ptr %n.addr.2, align 8
  %t9 = getelementptr inbounds %Node, ptr %t8, i32 0, i32 3
  %t10 = load ptr, ptr %t9, align 8
  %t11 = call ptr @strchr(ptr %t10, i32 58)
  %t12 = icmp ne ptr %t11, null
  store i1 %t12, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t13 = load i1, ptr %and.val2, align 1
  br i1 %t13, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t14 = load ptr, ptr %node.addr, align 8
  %t15 = load ptr, ptr %n.addr.2, align 8
  %t16 = getelementptr inbounds %Node, ptr %t15, i32 0, i32 1
  %t17 = load i32, ptr %t16, align 4
  %t18 = call ptr @desugar-symbol(ptr %t14, i32 %t17)
  ret ptr %t18
cond.end1:
  %t19 = load ptr, ptr %node.addr, align 8
  ret ptr %t19
}

define ptr @desugar-params(ptr %params.arg) {
entry:
  %params.addr = alloca ptr, align 8
  store ptr %params.arg, ptr %params.addr, align 8
  %n.addr.2 = alloca ptr, align 8
  %new-car.addr.9 = alloca ptr, align 8
  %new-cdr.addr.14 = alloca ptr, align 8
  %and.val3 = alloca i1, align 1
  %c.addr.31 = alloca ptr, align 8
  %t0 = load ptr, ptr %params.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret ptr null
cond.end0:
  %t3 = load ptr, ptr %params.addr, align 8
  store ptr %t3, ptr %n.addr.2, align 8
  %t4 = load ptr, ptr %n.addr.2, align 8
  %t5 = getelementptr inbounds %Node, ptr %t4, i32 0, i32 0
  %t6 = load i32, ptr %t5, align 4
  %t7 = icmp ne i32 %t6, 3
  br i1 %t7, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t8 = load ptr, ptr %params.addr, align 8
  ret ptr %t8
cond.end1:
  %t10 = load ptr, ptr %n.addr.2, align 8
  %t11 = getelementptr inbounds %Node, ptr %t10, i32 0, i32 4
  %t12 = load ptr, ptr %t11, align 8
  %t13 = call ptr @desugar-typed(ptr %t12)
  store ptr %t13, ptr %new-car.addr.9, align 8
  %t15 = load ptr, ptr %n.addr.2, align 8
  %t16 = getelementptr inbounds %Node, ptr %t15, i32 0, i32 5
  %t17 = load ptr, ptr %t16, align 8
  %t18 = call ptr @desugar-params(ptr %t17)
  store ptr %t18, ptr %new-cdr.addr.14, align 8
  %t19 = load ptr, ptr %new-car.addr.9, align 8
  %t20 = load ptr, ptr %n.addr.2, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 4
  %t22 = load ptr, ptr %t21, align 8
  %t23 = icmp eq ptr %t19, %t22
  store i1 %t23, ptr %and.val3, align 1
  br i1 %t23, label %and.rhs3, label %and.end3
and.rhs3:
  %t24 = load ptr, ptr %new-cdr.addr.14, align 8
  %t25 = load ptr, ptr %n.addr.2, align 8
  %t26 = getelementptr inbounds %Node, ptr %t25, i32 0, i32 5
  %t27 = load ptr, ptr %t26, align 8
  %t28 = icmp eq ptr %t24, %t27
  store i1 %t28, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t29 = load i1, ptr %and.val3, align 1
  br i1 %t29, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t30 = load ptr, ptr %params.addr, align 8
  ret ptr %t30
cond.end2:
  %t32 = call ptr @alloc-node()
  store ptr %t32, ptr %c.addr.31, align 8
  %t33 = load ptr, ptr %c.addr.31, align 8
  %t34 = getelementptr inbounds %Node, ptr %t33, i32 0, i32 0
  store i32 3, ptr %t34, align 4
  %t35 = load ptr, ptr %c.addr.31, align 8
  %t36 = load ptr, ptr %n.addr.2, align 8
  %t37 = getelementptr inbounds %Node, ptr %t36, i32 0, i32 1
  %t38 = load i32, ptr %t37, align 4
  %t39 = getelementptr inbounds %Node, ptr %t35, i32 0, i32 1
  store i32 %t38, ptr %t39, align 4
  %t40 = load ptr, ptr %c.addr.31, align 8
  %t41 = load ptr, ptr %new-car.addr.9, align 8
  %t42 = getelementptr inbounds %Node, ptr %t40, i32 0, i32 4
  store ptr %t41, ptr %t42, align 8
  %t43 = load ptr, ptr %c.addr.31, align 8
  %t44 = load ptr, ptr %new-cdr.addr.14, align 8
  %t45 = getelementptr inbounds %Node, ptr %t43, i32 0, i32 5
  store ptr %t44, ptr %t45, align 8
  %t46 = load ptr, ptr %c.addr.31, align 8
  ret ptr %t46
}

define ptr @desugar-let-bindings(ptr %binds.arg) {
entry:
  %binds.addr = alloca ptr, align 8
  store ptr %binds.arg, ptr %binds.addr, align 8
  %n.addr.2 = alloca ptr, align 8
  %result.addr.9 = alloca ptr, align 8
  %tail.addr.10 = alloca ptr, align 8
  %cur.addr.11 = alloca ptr, align 8
  %idx.addr.13 = alloca i32, align 4
  %changed.addr.14 = alloca i32, align 4
  %cn.addr.17 = alloca ptr, align 8
  %elem.addr.19 = alloca ptr, align 8
  %new-elem.addr.23 = alloca ptr, align 8
  %cell.addr.33 = alloca ptr, align 8
  %t0 = load ptr, ptr %binds.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret ptr null
cond.end0:
  %t3 = load ptr, ptr %binds.addr, align 8
  store ptr %t3, ptr %n.addr.2, align 8
  %t4 = load ptr, ptr %n.addr.2, align 8
  %t5 = getelementptr inbounds %Node, ptr %t4, i32 0, i32 0
  %t6 = load i32, ptr %t5, align 4
  %t7 = icmp ne i32 %t6, 3
  br i1 %t7, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t8 = load ptr, ptr %binds.addr, align 8
  ret ptr %t8
cond.end1:
  store ptr null, ptr %result.addr.9, align 8
  store ptr null, ptr %tail.addr.10, align 8
  %t12 = load ptr, ptr %binds.addr, align 8
  store ptr %t12, ptr %cur.addr.11, align 8
  store i32 0, ptr %idx.addr.13, align 4
  store i32 0, ptr %changed.addr.14, align 4
  br label %while.cond2
while.cond2:
  %t15 = load ptr, ptr %cur.addr.11, align 8
  %t16 = icmp ne ptr %t15, null
  br i1 %t16, label %while.body2, label %while.end2
while.body2:
  %t18 = load ptr, ptr %cur.addr.11, align 8
  store ptr %t18, ptr %cn.addr.17, align 8
  %t20 = load ptr, ptr %cn.addr.17, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 4
  %t22 = load ptr, ptr %t21, align 8
  store ptr %t22, ptr %elem.addr.19, align 8
  %t24 = load ptr, ptr %elem.addr.19, align 8
  store ptr %t24, ptr %new-elem.addr.23, align 8
  %t25 = load i32, ptr %idx.addr.13, align 4
  %t26 = srem i32 %t25, 2
  %t27 = icmp eq i32 %t26, 0
  br i1 %t27, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t28 = load ptr, ptr %elem.addr.19, align 8
  %t29 = call ptr @desugar-typed(ptr %t28)
  store ptr %t29, ptr %new-elem.addr.23, align 8
  br label %cond.end3
cond.end3:
  %t30 = load ptr, ptr %new-elem.addr.23, align 8
  %t31 = load ptr, ptr %elem.addr.19, align 8
  %t32 = icmp ne ptr %t30, %t31
  br i1 %t32, label %cond.then4.0, label %cond.end4
cond.then4.0:
  store i32 1, ptr %changed.addr.14, align 4
  br label %cond.end4
cond.end4:
  %t34 = load ptr, ptr %new-elem.addr.23, align 8
  %t35 = load ptr, ptr %cn.addr.17, align 8
  %t36 = getelementptr inbounds %Node, ptr %t35, i32 0, i32 1
  %t37 = load i32, ptr %t36, align 4
  %t38 = call ptr @make-cell(ptr %t34, ptr null, i32 %t37)
  store ptr %t38, ptr %cell.addr.33, align 8
  %t39 = load ptr, ptr %tail.addr.10, align 8
  %t40 = icmp eq ptr %t39, null
  br i1 %t40, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t41 = load ptr, ptr %cell.addr.33, align 8
  store ptr %t41, ptr %result.addr.9, align 8
  br label %cond.end5
cond.end5:
  %t42 = load ptr, ptr %tail.addr.10, align 8
  %t43 = icmp ne ptr %t42, null
  br i1 %t43, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t44 = load ptr, ptr %tail.addr.10, align 8
  %t45 = load ptr, ptr %cell.addr.33, align 8
  %t46 = getelementptr inbounds %Node, ptr %t44, i32 0, i32 5
  store ptr %t45, ptr %t46, align 8
  br label %cond.end6
cond.end6:
  %t47 = load ptr, ptr %cell.addr.33, align 8
  store ptr %t47, ptr %tail.addr.10, align 8
  %t48 = load ptr, ptr %cur.addr.11, align 8
  %t49 = getelementptr inbounds %Node, ptr %t48, i32 0, i32 5
  %t50 = load ptr, ptr %t49, align 8
  store ptr %t50, ptr %cur.addr.11, align 8
  %t51 = load i32, ptr %idx.addr.13, align 4
  %t52 = add nsw i32 %t51, 1
  store i32 %t52, ptr %idx.addr.13, align 4
  br label %while.cond2
while.end2:
  %t53 = load i32, ptr %changed.addr.14, align 4
  %t54 = icmp eq i32 %t53, 0
  br i1 %t54, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t55 = load ptr, ptr %binds.addr, align 8
  ret ptr %t55
cond.end7:
  %t56 = load ptr, ptr %result.addr.9, align 8
  ret ptr %t56
}

define ptr @desugar(ptr %forms.arg) {
entry:
  %forms.addr = alloca ptr, align 8
  store ptr %forms.arg, ptr %forms.addr, align 8
  %n.addr.2 = alloca ptr, align 8
  %new-car.addr.9 = alloca ptr, align 8
  %new-cdr.addr.14 = alloca ptr, align 8
  %and.val3 = alloca i1, align 1
  %c.addr.31 = alloca ptr, align 8
  %t0 = load ptr, ptr %forms.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret ptr null
cond.end0:
  %t3 = load ptr, ptr %forms.addr, align 8
  store ptr %t3, ptr %n.addr.2, align 8
  %t4 = load ptr, ptr %n.addr.2, align 8
  %t5 = getelementptr inbounds %Node, ptr %t4, i32 0, i32 0
  %t6 = load i32, ptr %t5, align 4
  %t7 = icmp ne i32 %t6, 3
  br i1 %t7, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t8 = load ptr, ptr %forms.addr, align 8
  ret ptr %t8
cond.end1:
  %t10 = load ptr, ptr %n.addr.2, align 8
  %t11 = getelementptr inbounds %Node, ptr %t10, i32 0, i32 4
  %t12 = load ptr, ptr %t11, align 8
  %t13 = call ptr @desugar-form(ptr %t12)
  store ptr %t13, ptr %new-car.addr.9, align 8
  %t15 = load ptr, ptr %n.addr.2, align 8
  %t16 = getelementptr inbounds %Node, ptr %t15, i32 0, i32 5
  %t17 = load ptr, ptr %t16, align 8
  %t18 = call ptr @desugar(ptr %t17)
  store ptr %t18, ptr %new-cdr.addr.14, align 8
  %t19 = load ptr, ptr %new-car.addr.9, align 8
  %t20 = load ptr, ptr %n.addr.2, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 4
  %t22 = load ptr, ptr %t21, align 8
  %t23 = icmp eq ptr %t19, %t22
  store i1 %t23, ptr %and.val3, align 1
  br i1 %t23, label %and.rhs3, label %and.end3
and.rhs3:
  %t24 = load ptr, ptr %new-cdr.addr.14, align 8
  %t25 = load ptr, ptr %n.addr.2, align 8
  %t26 = getelementptr inbounds %Node, ptr %t25, i32 0, i32 5
  %t27 = load ptr, ptr %t26, align 8
  %t28 = icmp eq ptr %t24, %t27
  store i1 %t28, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t29 = load i1, ptr %and.val3, align 1
  br i1 %t29, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t30 = load ptr, ptr %forms.addr, align 8
  ret ptr %t30
cond.end2:
  %t32 = call ptr @alloc-node()
  store ptr %t32, ptr %c.addr.31, align 8
  %t33 = load ptr, ptr %c.addr.31, align 8
  %t34 = getelementptr inbounds %Node, ptr %t33, i32 0, i32 0
  store i32 3, ptr %t34, align 4
  %t35 = load ptr, ptr %c.addr.31, align 8
  %t36 = load ptr, ptr %n.addr.2, align 8
  %t37 = getelementptr inbounds %Node, ptr %t36, i32 0, i32 1
  %t38 = load i32, ptr %t37, align 4
  %t39 = getelementptr inbounds %Node, ptr %t35, i32 0, i32 1
  store i32 %t38, ptr %t39, align 4
  %t40 = load ptr, ptr %c.addr.31, align 8
  %t41 = load ptr, ptr %new-car.addr.9, align 8
  %t42 = getelementptr inbounds %Node, ptr %t40, i32 0, i32 4
  store ptr %t41, ptr %t42, align 8
  %t43 = load ptr, ptr %c.addr.31, align 8
  %t44 = load ptr, ptr %new-cdr.addr.14, align 8
  %t45 = getelementptr inbounds %Node, ptr %t43, i32 0, i32 5
  store ptr %t44, ptr %t45, align 8
  %t46 = load ptr, ptr %c.addr.31, align 8
  ret ptr %t46
}

define ptr @desugar-form(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %f.addr.2 = alloca ptr, align 8
  %head.addr.13 = alloca ptr, align 8
  %h.addr.21 = alloca ptr, align 8
  %new-name.addr.32 = alloca ptr, align 8
  %new-params.addr.36 = alloca ptr, align 8
  %and.val7 = alloca i1, align 1
  %new-name.addr.79 = alloca ptr, align 8
  %new-rest.addr.110 = alloca ptr, align 8
  %new-name.addr.144 = alloca ptr, align 8
  %new-name.addr.170 = alloca ptr, align 8
  %new-params.addr.174 = alloca ptr, align 8
  %and.val21 = alloca i1, align 1
  %or.val22 = alloca i1, align 1
  %new-binds.addr.230 = alloca ptr, align 8
  %or.val28 = alloca i1, align 1
  %new-body.addr.263 = alloca ptr, align 8
  %t0 = load ptr, ptr %form.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret ptr null
cond.end0:
  %t3 = load ptr, ptr %form.addr, align 8
  store ptr %t3, ptr %f.addr.2, align 8
  %t4 = load ptr, ptr %f.addr.2, align 8
  %t5 = getelementptr inbounds %Node, ptr %t4, i32 0, i32 0
  %t6 = load i32, ptr %t5, align 4
  %t7 = icmp ne i32 %t6, 3
  br i1 %t7, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t8 = load ptr, ptr %form.addr, align 8
  ret ptr %t8
cond.end1:
  %t9 = load ptr, ptr %form.addr, align 8
  %t10 = call i32 @node-len(ptr %t9)
  %t11 = icmp eq i32 %t10, 0
  br i1 %t11, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t12 = load ptr, ptr %form.addr, align 8
  ret ptr %t12
cond.end2:
  %t14 = load ptr, ptr %form.addr, align 8
  %t15 = call ptr @node-at(ptr %t14, i32 0)
  store ptr %t15, ptr %head.addr.13, align 8
  %t16 = load ptr, ptr %head.addr.13, align 8
  %t17 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 0
  %t18 = load i32, ptr %t17, align 4
  %t19 = icmp ne i32 %t18, 2
  br i1 %t19, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t20 = load ptr, ptr %form.addr, align 8
  ret ptr %t20
cond.end3:
  %t22 = load ptr, ptr %head.addr.13, align 8
  %t23 = getelementptr inbounds %Node, ptr %t22, i32 0, i32 3
  %t24 = load ptr, ptr %t23, align 8
  store ptr %t24, ptr %h.addr.21, align 8
  %t25 = load ptr, ptr %h.addr.21, align 8
  %t26 = getelementptr inbounds [5 x i8], ptr @.str.585, i64 0, i64 0
  %t27 = call i32 @strcmp(ptr %t25, ptr %t26)
  %t28 = icmp eq i32 %t27, 0
  br i1 %t28, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t29 = load ptr, ptr %form.addr, align 8
  %t30 = call i32 @node-len(ptr %t29)
  %t31 = icmp sge i32 %t30, 3
  br i1 %t31, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t33 = load ptr, ptr %form.addr, align 8
  %t34 = call ptr @node-at(ptr %t33, i32 1)
  %t35 = call ptr @desugar-typed(ptr %t34)
  store ptr %t35, ptr %new-name.addr.32, align 8
  %t37 = load ptr, ptr %form.addr, align 8
  %t38 = call ptr @node-at(ptr %t37, i32 2)
  %t39 = call ptr @desugar-params(ptr %t38)
  store ptr %t39, ptr %new-params.addr.36, align 8
  %t40 = load ptr, ptr %new-name.addr.32, align 8
  %t41 = load ptr, ptr %form.addr, align 8
  %t42 = call ptr @node-at(ptr %t41, i32 1)
  %t43 = icmp eq ptr %t40, %t42
  store i1 %t43, ptr %and.val7, align 1
  br i1 %t43, label %and.rhs7, label %and.end7
and.rhs7:
  %t44 = load ptr, ptr %new-params.addr.36, align 8
  %t45 = load ptr, ptr %form.addr, align 8
  %t46 = call ptr @node-at(ptr %t45, i32 2)
  %t47 = icmp eq ptr %t44, %t46
  store i1 %t47, ptr %and.val7, align 1
  br label %and.end7
and.end7:
  %t48 = load i1, ptr %and.val7, align 1
  br i1 %t48, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t49 = load ptr, ptr %form.addr, align 8
  ret ptr %t49
cond.end6:
  %t50 = load ptr, ptr %head.addr.13, align 8
  %t51 = load ptr, ptr %new-name.addr.32, align 8
  %t52 = load ptr, ptr %new-params.addr.36, align 8
  %t53 = load ptr, ptr %f.addr.2, align 8
  %t54 = getelementptr inbounds %Node, ptr %t53, i32 0, i32 5
  %t55 = load ptr, ptr %t54, align 8
  %t56 = getelementptr inbounds %Node, ptr %t55, i32 0, i32 5
  %t57 = load ptr, ptr %t56, align 8
  %t58 = getelementptr inbounds %Node, ptr %t57, i32 0, i32 5
  %t59 = load ptr, ptr %t58, align 8
  %t60 = load ptr, ptr %f.addr.2, align 8
  %t61 = getelementptr inbounds %Node, ptr %t60, i32 0, i32 1
  %t62 = load i32, ptr %t61, align 4
  %t63 = call ptr @make-cell(ptr %t52, ptr %t59, i32 %t62)
  %t64 = load ptr, ptr %f.addr.2, align 8
  %t65 = getelementptr inbounds %Node, ptr %t64, i32 0, i32 1
  %t66 = load i32, ptr %t65, align 4
  %t67 = call ptr @make-cell(ptr %t51, ptr %t63, i32 %t66)
  %t68 = load ptr, ptr %f.addr.2, align 8
  %t69 = getelementptr inbounds %Node, ptr %t68, i32 0, i32 1
  %t70 = load i32, ptr %t69, align 4
  %t71 = call ptr @make-cell(ptr %t50, ptr %t67, i32 %t70)
  ret ptr %t71
cond.end5:
  br label %cond.end4
cond.end4:
  %t72 = load ptr, ptr %h.addr.21, align 8
  %t73 = getelementptr inbounds [7 x i8], ptr @.str.586, i64 0, i64 0
  %t74 = call i32 @strcmp(ptr %t72, ptr %t73)
  %t75 = icmp eq i32 %t74, 0
  br i1 %t75, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t76 = load ptr, ptr %form.addr, align 8
  %t77 = call i32 @node-len(ptr %t76)
  %t78 = icmp sge i32 %t77, 2
  br i1 %t78, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t80 = load ptr, ptr %form.addr, align 8
  %t81 = call ptr @node-at(ptr %t80, i32 1)
  %t82 = call ptr @desugar-typed(ptr %t81)
  store ptr %t82, ptr %new-name.addr.79, align 8
  %t83 = load ptr, ptr %new-name.addr.79, align 8
  %t84 = load ptr, ptr %form.addr, align 8
  %t85 = call ptr @node-at(ptr %t84, i32 1)
  %t86 = icmp eq ptr %t83, %t85
  br i1 %t86, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t87 = load ptr, ptr %form.addr, align 8
  ret ptr %t87
cond.end10:
  %t88 = load ptr, ptr %head.addr.13, align 8
  %t89 = load ptr, ptr %new-name.addr.79, align 8
  %t90 = load ptr, ptr %f.addr.2, align 8
  %t91 = getelementptr inbounds %Node, ptr %t90, i32 0, i32 5
  %t92 = load ptr, ptr %t91, align 8
  %t93 = getelementptr inbounds %Node, ptr %t92, i32 0, i32 5
  %t94 = load ptr, ptr %t93, align 8
  %t95 = load ptr, ptr %f.addr.2, align 8
  %t96 = getelementptr inbounds %Node, ptr %t95, i32 0, i32 1
  %t97 = load i32, ptr %t96, align 4
  %t98 = call ptr @make-cell(ptr %t89, ptr %t94, i32 %t97)
  %t99 = load ptr, ptr %f.addr.2, align 8
  %t100 = getelementptr inbounds %Node, ptr %t99, i32 0, i32 1
  %t101 = load i32, ptr %t100, align 4
  %t102 = call ptr @make-cell(ptr %t88, ptr %t98, i32 %t101)
  ret ptr %t102
cond.end9:
  br label %cond.end8
cond.end8:
  %t103 = load ptr, ptr %h.addr.21, align 8
  %t104 = getelementptr inbounds [10 x i8], ptr @.str.587, i64 0, i64 0
  %t105 = call i32 @strcmp(ptr %t103, ptr %t104)
  %t106 = icmp eq i32 %t105, 0
  br i1 %t106, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t107 = load ptr, ptr %form.addr, align 8
  %t108 = call i32 @node-len(ptr %t107)
  %t109 = icmp sge i32 %t108, 2
  br i1 %t109, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t111 = load ptr, ptr %f.addr.2, align 8
  %t112 = getelementptr inbounds %Node, ptr %t111, i32 0, i32 5
  %t113 = load ptr, ptr %t112, align 8
  %t114 = getelementptr inbounds %Node, ptr %t113, i32 0, i32 5
  %t115 = load ptr, ptr %t114, align 8
  %t116 = call ptr @desugar-params(ptr %t115)
  store ptr %t116, ptr %new-rest.addr.110, align 8
  %t117 = load ptr, ptr %new-rest.addr.110, align 8
  %t118 = load ptr, ptr %f.addr.2, align 8
  %t119 = getelementptr inbounds %Node, ptr %t118, i32 0, i32 5
  %t120 = load ptr, ptr %t119, align 8
  %t121 = getelementptr inbounds %Node, ptr %t120, i32 0, i32 5
  %t122 = load ptr, ptr %t121, align 8
  %t123 = icmp eq ptr %t117, %t122
  br i1 %t123, label %cond.then13.0, label %cond.end13
cond.then13.0:
  %t124 = load ptr, ptr %form.addr, align 8
  ret ptr %t124
cond.end13:
  %t125 = load ptr, ptr %head.addr.13, align 8
  %t126 = load ptr, ptr %form.addr, align 8
  %t127 = call ptr @node-at(ptr %t126, i32 1)
  %t128 = load ptr, ptr %new-rest.addr.110, align 8
  %t129 = load ptr, ptr %f.addr.2, align 8
  %t130 = getelementptr inbounds %Node, ptr %t129, i32 0, i32 1
  %t131 = load i32, ptr %t130, align 4
  %t132 = call ptr @make-cell(ptr %t127, ptr %t128, i32 %t131)
  %t133 = load ptr, ptr %f.addr.2, align 8
  %t134 = getelementptr inbounds %Node, ptr %t133, i32 0, i32 1
  %t135 = load i32, ptr %t134, align 4
  %t136 = call ptr @make-cell(ptr %t125, ptr %t132, i32 %t135)
  ret ptr %t136
cond.end12:
  br label %cond.end11
cond.end11:
  %t137 = load ptr, ptr %h.addr.21, align 8
  %t138 = getelementptr inbounds [7 x i8], ptr @.str.588, i64 0, i64 0
  %t139 = call i32 @strcmp(ptr %t137, ptr %t138)
  %t140 = icmp eq i32 %t139, 0
  br i1 %t140, label %cond.then14.0, label %cond.end14
cond.then14.0:
  %t141 = load ptr, ptr %form.addr, align 8
  %t142 = call i32 @node-len(ptr %t141)
  %t143 = icmp eq i32 %t142, 2
  br i1 %t143, label %cond.then15.0, label %cond.end15
cond.then15.0:
  %t145 = load ptr, ptr %form.addr, align 8
  %t146 = call ptr @node-at(ptr %t145, i32 1)
  %t147 = call ptr @desugar-typed(ptr %t146)
  store ptr %t147, ptr %new-name.addr.144, align 8
  %t148 = load ptr, ptr %new-name.addr.144, align 8
  %t149 = load ptr, ptr %form.addr, align 8
  %t150 = call ptr @node-at(ptr %t149, i32 1)
  %t151 = icmp eq ptr %t148, %t150
  br i1 %t151, label %cond.then16.0, label %cond.end16
cond.then16.0:
  %t152 = load ptr, ptr %form.addr, align 8
  ret ptr %t152
cond.end16:
  %t153 = load ptr, ptr %head.addr.13, align 8
  %t154 = load ptr, ptr %new-name.addr.144, align 8
  %t155 = load ptr, ptr %f.addr.2, align 8
  %t156 = getelementptr inbounds %Node, ptr %t155, i32 0, i32 1
  %t157 = load i32, ptr %t156, align 4
  %t158 = call ptr @make-cell(ptr %t154, ptr null, i32 %t157)
  %t159 = load ptr, ptr %f.addr.2, align 8
  %t160 = getelementptr inbounds %Node, ptr %t159, i32 0, i32 1
  %t161 = load i32, ptr %t160, align 4
  %t162 = call ptr @make-cell(ptr %t153, ptr %t158, i32 %t161)
  ret ptr %t162
cond.end15:
  br label %cond.end14
cond.end14:
  %t163 = load ptr, ptr %h.addr.21, align 8
  %t164 = getelementptr inbounds [8 x i8], ptr @.str.589, i64 0, i64 0
  %t165 = call i32 @strcmp(ptr %t163, ptr %t164)
  %t166 = icmp eq i32 %t165, 0
  br i1 %t166, label %cond.then17.0, label %cond.end17
cond.then17.0:
  %t167 = load ptr, ptr %form.addr, align 8
  %t168 = call i32 @node-len(ptr %t167)
  %t169 = icmp sge i32 %t168, 2
  br i1 %t169, label %cond.then18.0, label %cond.end18
cond.then18.0:
  %t171 = load ptr, ptr %form.addr, align 8
  %t172 = call ptr @node-at(ptr %t171, i32 1)
  %t173 = call ptr @desugar-typed(ptr %t172)
  store ptr %t173, ptr %new-name.addr.170, align 8
  store ptr null, ptr %new-params.addr.174, align 8
  %t175 = load ptr, ptr %form.addr, align 8
  %t176 = call i32 @node-len(ptr %t175)
  %t177 = icmp eq i32 %t176, 3
  br i1 %t177, label %cond.then19.0, label %cond.end19
cond.then19.0:
  %t178 = load ptr, ptr %form.addr, align 8
  %t179 = call ptr @node-at(ptr %t178, i32 2)
  %t180 = call ptr @desugar-params(ptr %t179)
  store ptr %t180, ptr %new-params.addr.174, align 8
  br label %cond.end19
cond.end19:
  %t181 = load ptr, ptr %new-name.addr.170, align 8
  %t182 = load ptr, ptr %form.addr, align 8
  %t183 = call ptr @node-at(ptr %t182, i32 1)
  %t184 = icmp eq ptr %t181, %t183
  store i1 %t184, ptr %and.val21, align 1
  br i1 %t184, label %and.rhs21, label %and.end21
and.rhs21:
  %t185 = load ptr, ptr %form.addr, align 8
  %t186 = call i32 @node-len(ptr %t185)
  %t187 = icmp eq i32 %t186, 2
  store i1 %t187, ptr %or.val22, align 1
  br i1 %t187, label %or.end22, label %or.rhs22
or.rhs22:
  %t188 = load ptr, ptr %new-params.addr.174, align 8
  %t189 = load ptr, ptr %form.addr, align 8
  %t190 = call ptr @node-at(ptr %t189, i32 2)
  %t191 = icmp eq ptr %t188, %t190
  store i1 %t191, ptr %or.val22, align 1
  br label %or.end22
or.end22:
  %t192 = load i1, ptr %or.val22, align 1
  store i1 %t192, ptr %and.val21, align 1
  br label %and.end21
and.end21:
  %t193 = load i1, ptr %and.val21, align 1
  br i1 %t193, label %cond.then20.0, label %cond.end20
cond.then20.0:
  %t194 = load ptr, ptr %form.addr, align 8
  ret ptr %t194
cond.end20:
  %t195 = load ptr, ptr %form.addr, align 8
  %t196 = call i32 @node-len(ptr %t195)
  %t197 = icmp eq i32 %t196, 3
  br i1 %t197, label %cond.then23.0, label %cond.end23
cond.then23.0:
  %t198 = load ptr, ptr %head.addr.13, align 8
  %t199 = load ptr, ptr %new-name.addr.170, align 8
  %t200 = load ptr, ptr %new-params.addr.174, align 8
  %t201 = load ptr, ptr %f.addr.2, align 8
  %t202 = getelementptr inbounds %Node, ptr %t201, i32 0, i32 1
  %t203 = load i32, ptr %t202, align 4
  %t204 = call ptr @make-cell(ptr %t200, ptr null, i32 %t203)
  %t205 = load ptr, ptr %f.addr.2, align 8
  %t206 = getelementptr inbounds %Node, ptr %t205, i32 0, i32 1
  %t207 = load i32, ptr %t206, align 4
  %t208 = call ptr @make-cell(ptr %t199, ptr %t204, i32 %t207)
  %t209 = load ptr, ptr %f.addr.2, align 8
  %t210 = getelementptr inbounds %Node, ptr %t209, i32 0, i32 1
  %t211 = load i32, ptr %t210, align 4
  %t212 = call ptr @make-cell(ptr %t198, ptr %t208, i32 %t211)
  ret ptr %t212
cond.end23:
  %t213 = load ptr, ptr %head.addr.13, align 8
  %t214 = load ptr, ptr %new-name.addr.170, align 8
  %t215 = load ptr, ptr %f.addr.2, align 8
  %t216 = getelementptr inbounds %Node, ptr %t215, i32 0, i32 1
  %t217 = load i32, ptr %t216, align 4
  %t218 = call ptr @make-cell(ptr %t214, ptr null, i32 %t217)
  %t219 = load ptr, ptr %f.addr.2, align 8
  %t220 = getelementptr inbounds %Node, ptr %t219, i32 0, i32 1
  %t221 = load i32, ptr %t220, align 4
  %t222 = call ptr @make-cell(ptr %t213, ptr %t218, i32 %t221)
  ret ptr %t222
cond.end18:
  br label %cond.end17
cond.end17:
  %t223 = load ptr, ptr %h.addr.21, align 8
  %t224 = getelementptr inbounds [4 x i8], ptr @.str.590, i64 0, i64 0
  %t225 = call i32 @strcmp(ptr %t223, ptr %t224)
  %t226 = icmp eq i32 %t225, 0
  br i1 %t226, label %cond.then24.0, label %cond.end24
cond.then24.0:
  %t227 = load ptr, ptr %form.addr, align 8
  %t228 = call i32 @node-len(ptr %t227)
  %t229 = icmp sge i32 %t228, 2
  br i1 %t229, label %cond.then25.0, label %cond.end25
cond.then25.0:
  %t231 = load ptr, ptr %form.addr, align 8
  %t232 = call ptr @node-at(ptr %t231, i32 1)
  %t233 = call ptr @desugar-let-bindings(ptr %t232)
  store ptr %t233, ptr %new-binds.addr.230, align 8
  %t234 = load ptr, ptr %new-binds.addr.230, align 8
  %t235 = load ptr, ptr %form.addr, align 8
  %t236 = call ptr @node-at(ptr %t235, i32 1)
  %t237 = icmp eq ptr %t234, %t236
  br i1 %t237, label %cond.then26.0, label %cond.end26
cond.then26.0:
  %t238 = load ptr, ptr %form.addr, align 8
  ret ptr %t238
cond.end26:
  %t239 = load ptr, ptr %head.addr.13, align 8
  %t240 = load ptr, ptr %new-binds.addr.230, align 8
  %t241 = load ptr, ptr %f.addr.2, align 8
  %t242 = getelementptr inbounds %Node, ptr %t241, i32 0, i32 5
  %t243 = load ptr, ptr %t242, align 8
  %t244 = getelementptr inbounds %Node, ptr %t243, i32 0, i32 5
  %t245 = load ptr, ptr %t244, align 8
  %t246 = load ptr, ptr %f.addr.2, align 8
  %t247 = getelementptr inbounds %Node, ptr %t246, i32 0, i32 1
  %t248 = load i32, ptr %t247, align 4
  %t249 = call ptr @make-cell(ptr %t240, ptr %t245, i32 %t248)
  %t250 = load ptr, ptr %f.addr.2, align 8
  %t251 = getelementptr inbounds %Node, ptr %t250, i32 0, i32 1
  %t252 = load i32, ptr %t251, align 4
  %t253 = call ptr @make-cell(ptr %t239, ptr %t249, i32 %t252)
  ret ptr %t253
cond.end25:
  br label %cond.end24
cond.end24:
  %t254 = load ptr, ptr %h.addr.21, align 8
  %t255 = getelementptr inbounds [13 x i8], ptr @.str.591, i64 0, i64 0
  %t256 = call i32 @strcmp(ptr %t254, ptr %t255)
  %t257 = icmp eq i32 %t256, 0
  store i1 %t257, ptr %or.val28, align 1
  br i1 %t257, label %or.end28, label %or.rhs28
or.rhs28:
  %t258 = load ptr, ptr %h.addr.21, align 8
  %t259 = getelementptr inbounds [3 x i8], ptr @.str.592, i64 0, i64 0
  %t260 = call i32 @strcmp(ptr %t258, ptr %t259)
  %t261 = icmp eq i32 %t260, 0
  store i1 %t261, ptr %or.val28, align 1
  br label %or.end28
or.end28:
  %t262 = load i1, ptr %or.val28, align 1
  br i1 %t262, label %cond.then27.0, label %cond.end27
cond.then27.0:
  %t264 = load ptr, ptr %f.addr.2, align 8
  %t265 = getelementptr inbounds %Node, ptr %t264, i32 0, i32 5
  %t266 = load ptr, ptr %t265, align 8
  %t267 = call ptr @desugar(ptr %t266)
  store ptr %t267, ptr %new-body.addr.263, align 8
  %t268 = load ptr, ptr %new-body.addr.263, align 8
  %t269 = load ptr, ptr %f.addr.2, align 8
  %t270 = getelementptr inbounds %Node, ptr %t269, i32 0, i32 5
  %t271 = load ptr, ptr %t270, align 8
  %t272 = icmp eq ptr %t268, %t271
  br i1 %t272, label %cond.then29.0, label %cond.end29
cond.then29.0:
  %t273 = load ptr, ptr %form.addr, align 8
  ret ptr %t273
cond.end29:
  %t274 = load ptr, ptr %head.addr.13, align 8
  %t275 = load ptr, ptr %new-body.addr.263, align 8
  %t276 = load ptr, ptr %f.addr.2, align 8
  %t277 = getelementptr inbounds %Node, ptr %t276, i32 0, i32 1
  %t278 = load i32, ptr %t277, align 4
  %t279 = call ptr @make-cell(ptr %t274, ptr %t275, i32 %t278)
  ret ptr %t279
cond.end27:
  %t280 = load ptr, ptr %form.addr, align 8
  ret ptr %t280
}

define void @prescan-defn-signatures(ptr %forms.arg) {
entry:
  %forms.addr = alloca ptr, align 8
  store ptr %forms.arg, ptr %forms.addr, align 8
  %fc.addr.0 = alloca ptr, align 8
  %f.addr.4 = alloca ptr, align 8
  %and.val2 = alloca i1, align 1
  %and.val3 = alloca i1, align 1
  %and.val4 = alloca i1, align 1
  %and.val5 = alloca i1, align 1
  %name-node.addr.33 = alloca ptr, align 8
  %params-node.addr.36 = alloca ptr, align 8
  %fname.addr.42 = alloca ptr, align 8
  %ret-name.addr.43 = alloca ptr, align 8
  %ret.addr.47 = alloca ptr, align 8
  %nparams.addr.53 = alloca i32, align 4
  %ptypes.addr.56 = alloca ptr, align 8
  %j.addr.64 = alloca i32, align 4
  %p.addr.68 = alloca ptr, align 8
  %pn.addr.72 = alloca ptr, align 8
  %pty.addr.73 = alloca ptr, align 8
  %ft.addr.93 = alloca ptr, align 8
  %t1 = load ptr, ptr %forms.addr, align 8
  store ptr %t1, ptr %fc.addr.0, align 8
  br label %while.cond0
while.cond0:
  %t2 = load ptr, ptr %fc.addr.0, align 8
  %t3 = icmp ne ptr %t2, null
  br i1 %t3, label %while.body0, label %while.end0
while.body0:
  %t5 = load ptr, ptr %fc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 4
  %t7 = load ptr, ptr %t6, align 8
  store ptr %t7, ptr %f.addr.4, align 8
  %t8 = load ptr, ptr %f.addr.4, align 8
  %t9 = icmp ne ptr %t8, null
  store i1 %t9, ptr %and.val3, align 1
  br i1 %t9, label %and.rhs3, label %and.end3
and.rhs3:
  %t10 = load ptr, ptr %f.addr.4, align 8
  %t11 = getelementptr inbounds %Node, ptr %t10, i32 0, i32 0
  %t12 = load i32, ptr %t11, align 4
  %t13 = icmp eq i32 %t12, 3
  store i1 %t13, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t14 = load i1, ptr %and.val3, align 1
  store i1 %t14, ptr %and.val2, align 1
  br i1 %t14, label %and.rhs2, label %and.end2
and.rhs2:
  %t15 = load ptr, ptr %f.addr.4, align 8
  %t16 = call i32 @node-len(ptr %t15)
  %t17 = icmp sge i32 %t16, 4
  store i1 %t17, ptr %and.val4, align 1
  br i1 %t17, label %and.rhs4, label %and.end4
and.rhs4:
  %t18 = load ptr, ptr %f.addr.4, align 8
  %t19 = call ptr @node-at(ptr %t18, i32 0)
  %t20 = getelementptr inbounds %Node, ptr %t19, i32 0, i32 0
  %t21 = load i32, ptr %t20, align 4
  %t22 = icmp eq i32 %t21, 2
  store i1 %t22, ptr %and.val5, align 1
  br i1 %t22, label %and.rhs5, label %and.end5
and.rhs5:
  %t23 = load ptr, ptr %f.addr.4, align 8
  %t24 = call ptr @node-at(ptr %t23, i32 0)
  %t25 = getelementptr inbounds %Node, ptr %t24, i32 0, i32 3
  %t26 = load ptr, ptr %t25, align 8
  %t27 = getelementptr inbounds [5 x i8], ptr @.str.593, i64 0, i64 0
  %t28 = call i32 @strcmp(ptr %t26, ptr %t27)
  %t29 = icmp eq i32 %t28, 0
  store i1 %t29, ptr %and.val5, align 1
  br label %and.end5
and.end5:
  %t30 = load i1, ptr %and.val5, align 1
  store i1 %t30, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t31 = load i1, ptr %and.val4, align 1
  store i1 %t31, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t32 = load i1, ptr %and.val2, align 1
  br i1 %t32, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t34 = load ptr, ptr %f.addr.4, align 8
  %t35 = call ptr @node-at(ptr %t34, i32 1)
  store ptr %t35, ptr %name-node.addr.33, align 8
  %t37 = load ptr, ptr %f.addr.4, align 8
  %t38 = call ptr @node-at(ptr %t37, i32 2)
  store ptr %t38, ptr %params-node.addr.36, align 8
  %t39 = load ptr, ptr %params-node.addr.36, align 8
  %t40 = call i32 @node-is-list(ptr %t39)
  %t41 = icmp ne i32 %t40, 0
  br i1 %t41, label %cond.then6.0, label %cond.end6
cond.then6.0:
  store ptr null, ptr %fname.addr.42, align 8
  store ptr null, ptr %ret-name.addr.43, align 8
  %t44 = load ptr, ptr %name-node.addr.33, align 8
  call void @extract-name-type(ptr %t44, ptr %fname.addr.42, ptr %ret-name.addr.43)
  %t45 = load ptr, ptr %ret-name.addr.43, align 8
  %t46 = icmp ne ptr %t45, null
  br i1 %t46, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t48 = load ptr, ptr %ret-name.addr.43, align 8
  %t49 = load ptr, ptr %name-node.addr.33, align 8
  %t50 = getelementptr inbounds %Node, ptr %t49, i32 0, i32 1
  %t51 = load i32, ptr %t50, align 4
  %t52 = call ptr @parse-type-name(ptr %t48, i32 %t51)
  store ptr %t52, ptr %ret.addr.47, align 8
  %t54 = load ptr, ptr %params-node.addr.36, align 8
  %t55 = call i32 @node-len(ptr %t54)
  store i32 %t55, ptr %nparams.addr.53, align 4
  store ptr null, ptr %ptypes.addr.56, align 8
  %t57 = load i32, ptr %nparams.addr.53, align 4
  %t58 = icmp sgt i32 %t57, 0
  br i1 %t58, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t59 = load i32, ptr %nparams.addr.53, align 4
  %t60 = call i64 @i64(i32 %t59)
  %t61 = call i64 @i64(i32 8)
  %t62 = mul nsw i64 %t60, %t61
  %t63 = call ptr @arena-alloc(i64 %t62)
  store ptr %t63, ptr %ptypes.addr.56, align 8
  br label %cond.end8
cond.end8:
  store i32 0, ptr %j.addr.64, align 4
  br label %while.cond9
while.cond9:
  %t65 = load i32, ptr %j.addr.64, align 4
  %t66 = load i32, ptr %nparams.addr.53, align 4
  %t67 = icmp slt i32 %t65, %t66
  br i1 %t67, label %while.body9, label %while.end9
while.body9:
  %t69 = load ptr, ptr %params-node.addr.36, align 8
  %t70 = load i32, ptr %j.addr.64, align 4
  %t71 = call ptr @node-at(ptr %t69, i32 %t70)
  store ptr %t71, ptr %p.addr.68, align 8
  store ptr null, ptr %pn.addr.72, align 8
  %t74 = load ptr, ptr %p.addr.68, align 8
  %t75 = load ptr, ptr %p.addr.68, align 8
  %t76 = getelementptr inbounds %Node, ptr %t75, i32 0, i32 1
  %t77 = load i32, ptr %t76, align 4
  %t78 = call ptr @extract-name-and-type(ptr %t74, ptr %pn.addr.72, i32 %t77)
  store ptr %t78, ptr %pty.addr.73, align 8
  %t79 = load ptr, ptr %pty.addr.73, align 8
  %t80 = icmp ne ptr %t79, null
  br i1 %t80, label %cond.then10.0, label %cond.test10.1
cond.then10.0:
  %t81 = load ptr, ptr %ptypes.addr.56, align 8
  %t82 = load i32, ptr %j.addr.64, align 4
  %t83 = sext i32 %t82 to i64
  %t84 = load ptr, ptr %pty.addr.73, align 8
  %t85 = getelementptr inbounds ptr, ptr %t81, i64 %t83
  store ptr %t84, ptr %t85, align 8
  br label %cond.end10
cond.test10.1:
  br i1 1, label %cond.then10.1, label %cond.end10
cond.then10.1:
  %t86 = load ptr, ptr %ptypes.addr.56, align 8
  %t87 = load i32, ptr %j.addr.64, align 4
  %t88 = sext i32 %t87 to i64
  %t89 = load ptr, ptr @ty-i32, align 8
  %t90 = getelementptr inbounds ptr, ptr %t86, i64 %t88
  store ptr %t89, ptr %t90, align 8
  br label %cond.end10
cond.end10:
  %t91 = load i32, ptr %j.addr.64, align 4
  %t92 = add nsw i32 %t91, 1
  store i32 %t92, ptr %j.addr.64, align 4
  br label %while.cond9
while.end9:
  %t94 = call ptr @make-type(i32 11)
  store ptr %t94, ptr %ft.addr.93, align 8
  %t95 = load ptr, ptr %ft.addr.93, align 8
  %t96 = load ptr, ptr %ret.addr.47, align 8
  %t97 = getelementptr inbounds %Type, ptr %t95, i32 0, i32 1
  store ptr %t96, ptr %t97, align 8
  %t98 = load ptr, ptr %ft.addr.93, align 8
  %t99 = load i32, ptr %nparams.addr.53, align 4
  %t100 = getelementptr inbounds %Type, ptr %t98, i32 0, i32 3
  store i32 %t99, ptr %t100, align 4
  %t101 = load ptr, ptr %ft.addr.93, align 8
  %t102 = load ptr, ptr %ptypes.addr.56, align 8
  %t103 = getelementptr inbounds %Type, ptr %t101, i32 0, i32 2
  store ptr %t102, ptr %t103, align 8
  %t104 = load ptr, ptr @g-globals, align 8
  %t105 = load ptr, ptr %fname.addr.42, align 8
  %t106 = load ptr, ptr %ft.addr.93, align 8
  %t107 = getelementptr inbounds [4 x i8], ptr @.str.594, i64 0, i64 0
  %t108 = load ptr, ptr %fname.addr.42, align 8
  %t109 = call ptr @fmt-s(ptr %t107, ptr %t108)
  %t110 = call ptr @scope-define(ptr %t104, ptr %t105, ptr %t106, ptr %t109, i32 0)
  br label %cond.end7
cond.end7:
  br label %cond.end6
cond.end6:
  br label %cond.end1
cond.end1:
  %t111 = load ptr, ptr %fc.addr.0, align 8
  %t112 = getelementptr inbounds %Node, ptr %t111, i32 0, i32 5
  %t113 = load ptr, ptr %t112, align 8
  store ptr %t113, ptr %fc.addr.0, align 8
  br label %while.cond0
while.end0:
  ret void
}

define void @emit-def-rmacro(ptr %call.arg) {
entry:
  %call.addr = alloca ptr, align 8
  store ptr %call.arg, ptr %call.addr, align 8
  %cc.addr.0 = alloca ptr, align 8
  %prefix-node.addr.9 = alloca ptr, align 8
  %sym-node.addr.12 = alloca ptr, align 8
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
  %t8 = getelementptr inbounds [49 x i8], ptr @.str.595, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %cc.addr.0, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %prefix-node.addr.9, align 8
  %t13 = load ptr, ptr %cc.addr.0, align 8
  %t14 = call ptr @node-at(ptr %t13, i32 2)
  store ptr %t14, ptr %sym-node.addr.12, align 8
  %t15 = load ptr, ptr %prefix-node.addr.9, align 8
  %t16 = getelementptr inbounds %Node, ptr %t15, i32 0, i32 0
  %t17 = load i32, ptr %t16, align 4
  %t18 = icmp ne i32 %t17, 1
  br i1 %t18, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t19 = load ptr, ptr %prefix-node.addr.9, align 8
  %t20 = getelementptr inbounds %Node, ptr %t19, i32 0, i32 1
  %t21 = load i32, ptr %t20, align 4
  %t22 = getelementptr inbounds [36 x i8], ptr @.str.596, i64 0, i64 0
  call void @die-at(i32 %t21, ptr %t22)
  br label %cond.end1
cond.end1:
  %t23 = load ptr, ptr %sym-node.addr.12, align 8
  %t24 = getelementptr inbounds %Node, ptr %t23, i32 0, i32 0
  %t25 = load i32, ptr %t24, align 4
  %t26 = icmp ne i32 %t25, 2
  br i1 %t26, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t27 = load ptr, ptr %sym-node.addr.12, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 1
  %t29 = load i32, ptr %t28, align 4
  %t30 = getelementptr inbounds [41 x i8], ptr @.str.597, i64 0, i64 0
  call void @die-at(i32 %t29, ptr %t30)
  br label %cond.end2
cond.end2:
  %t31 = load ptr, ptr %prefix-node.addr.9, align 8
  %t32 = getelementptr inbounds %Node, ptr %t31, i32 0, i32 3
  %t33 = load ptr, ptr %t32, align 8
  %t34 = load ptr, ptr %sym-node.addr.12, align 8
  %t35 = getelementptr inbounds %Node, ptr %t34, i32 0, i32 3
  %t36 = load ptr, ptr %t35, align 8
  call void @register-rmacro(ptr %t33, ptr %t36)
  ret void
}

define void @emit-toplevel-forms(ptr %forms.arg) {
entry:
  %forms.addr = alloca ptr, align 8
  store ptr %forms.arg, ptr %forms.addr, align 8
  %fc.addr.1 = alloca ptr, align 8
  %f.addr.5 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %or.val3 = alloca i1, align 1
  %or.val4 = alloca i1, align 1
  %h.addr.30 = alloca ptr, align 8
  %t0 = load ptr, ptr %forms.addr, align 8
  call void @prescan-defn-signatures(ptr %t0)
  %t2 = load ptr, ptr %forms.addr, align 8
  store ptr %t2, ptr %fc.addr.1, align 8
  br label %while.cond0
while.cond0:
  %t3 = load ptr, ptr %fc.addr.1, align 8
  %t4 = icmp ne ptr %t3, null
  br i1 %t4, label %while.body0, label %while.end0
while.body0:
  %t6 = load ptr, ptr %fc.addr.1, align 8
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 4
  %t8 = load ptr, ptr %t7, align 8
  store ptr %t8, ptr %f.addr.5, align 8
  %t9 = load ptr, ptr %f.addr.5, align 8
  %t10 = icmp eq ptr %t9, null
  store i1 %t10, ptr %or.val3, align 1
  br i1 %t10, label %or.end3, label %or.rhs3
or.rhs3:
  %t11 = load ptr, ptr %f.addr.5, align 8
  %t12 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 0
  %t13 = load i32, ptr %t12, align 4
  %t14 = icmp ne i32 %t13, 3
  store i1 %t14, ptr %or.val3, align 1
  br label %or.end3
or.end3:
  %t15 = load i1, ptr %or.val3, align 1
  store i1 %t15, ptr %or.val2, align 1
  br i1 %t15, label %or.end2, label %or.rhs2
or.rhs2:
  %t16 = load ptr, ptr %f.addr.5, align 8
  %t17 = call i32 @node-len(ptr %t16)
  %t18 = icmp eq i32 %t17, 0
  store i1 %t18, ptr %or.val4, align 1
  br i1 %t18, label %or.end4, label %or.rhs4
or.rhs4:
  %t19 = load ptr, ptr %f.addr.5, align 8
  %t20 = call ptr @node-at(ptr %t19, i32 0)
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 0
  %t22 = load i32, ptr %t21, align 4
  %t23 = icmp ne i32 %t22, 2
  store i1 %t23, ptr %or.val4, align 1
  br label %or.end4
or.end4:
  %t24 = load i1, ptr %or.val4, align 1
  store i1 %t24, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t25 = load i1, ptr %or.val2, align 1
  br i1 %t25, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t26 = load ptr, ptr %f.addr.5, align 8
  %t27 = getelementptr inbounds %Node, ptr %t26, i32 0, i32 1
  %t28 = load i32, ptr %t27, align 4
  %t29 = getelementptr inbounds [53 x i8], ptr @.str.598, i64 0, i64 0
  call void @die-at(i32 %t28, ptr %t29)
  br label %cond.end1
cond.end1:
  %t31 = load ptr, ptr %f.addr.5, align 8
  %t32 = call ptr @node-at(ptr %t31, i32 0)
  %t33 = getelementptr inbounds %Node, ptr %t32, i32 0, i32 3
  %t34 = load ptr, ptr %t33, align 8
  store ptr %t34, ptr %h.addr.30, align 8
  %t35 = load ptr, ptr %h.addr.30, align 8
  %t36 = getelementptr inbounds [9 x i8], ptr @.str.599, i64 0, i64 0
  %t37 = call i32 @strcmp(ptr %t35, ptr %t36)
  %t38 = icmp eq i32 %t37, 0
  br i1 %t38, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t39 = load ptr, ptr %f.addr.5, align 8
  call void @emit-defconst(ptr %t39)
  br label %cond.end5
cond.test5.1:
  %t40 = load ptr, ptr %h.addr.30, align 8
  %t41 = getelementptr inbounds [8 x i8], ptr @.str.600, i64 0, i64 0
  %t42 = call i32 @strcmp(ptr %t40, ptr %t41)
  %t43 = icmp eq i32 %t42, 0
  br i1 %t43, label %cond.then5.1, label %cond.test5.2
cond.then5.1:
  %t44 = load ptr, ptr %f.addr.5, align 8
  call void @emit-defenum(ptr %t44)
  br label %cond.end5
cond.test5.2:
  %t45 = load ptr, ptr %h.addr.30, align 8
  %t46 = getelementptr inbounds [7 x i8], ptr @.str.601, i64 0, i64 0
  %t47 = call i32 @strcmp(ptr %t45, ptr %t46)
  %t48 = icmp eq i32 %t47, 0
  br i1 %t48, label %cond.then5.2, label %cond.test5.3
cond.then5.2:
  %t49 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t49, ptr @g-out, align 8
  %t50 = load ptr, ptr %f.addr.5, align 8
  call void @emit-defvar(ptr %t50)
  br label %cond.end5
cond.test5.3:
  %t51 = load ptr, ptr %h.addr.30, align 8
  %t52 = getelementptr inbounds [10 x i8], ptr @.str.602, i64 0, i64 0
  %t53 = call i32 @strcmp(ptr %t51, ptr %t52)
  %t54 = icmp eq i32 %t53, 0
  br i1 %t54, label %cond.then5.3, label %cond.test5.4
cond.then5.3:
  %t55 = load ptr, ptr @g-type-stream, align 8
  store ptr %t55, ptr @g-out, align 8
  %t56 = load ptr, ptr %f.addr.5, align 8
  call void @emit-defstruct(ptr %t56)
  br label %cond.end5
cond.test5.4:
  %t57 = load ptr, ptr %h.addr.30, align 8
  %t58 = getelementptr inbounds [8 x i8], ptr @.str.603, i64 0, i64 0
  %t59 = call i32 @strcmp(ptr %t57, ptr %t58)
  %t60 = icmp eq i32 %t59, 0
  br i1 %t60, label %cond.then5.4, label %cond.test5.5
cond.then5.4:
  %t61 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t61, ptr @g-out, align 8
  %t62 = load ptr, ptr %f.addr.5, align 8
  call void @emit-include(ptr %t62)
  br label %cond.end5
cond.test5.5:
  %t63 = load ptr, ptr %h.addr.30, align 8
  %t64 = getelementptr inbounds [7 x i8], ptr @.str.604, i64 0, i64 0
  %t65 = call i32 @strcmp(ptr %t63, ptr %t64)
  %t66 = icmp eq i32 %t65, 0
  br i1 %t66, label %cond.then5.5, label %cond.test5.6
cond.then5.5:
  %t67 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t67, ptr @g-out, align 8
  %t68 = load ptr, ptr %f.addr.5, align 8
  call void @emit-extern(ptr %t68)
  br label %cond.end5
cond.test5.6:
  %t69 = load ptr, ptr %h.addr.30, align 8
  %t70 = getelementptr inbounds [5 x i8], ptr @.str.605, i64 0, i64 0
  %t71 = call i32 @strcmp(ptr %t69, ptr %t70)
  %t72 = icmp eq i32 %t71, 0
  br i1 %t72, label %cond.then5.6, label %cond.test5.7
cond.then5.6:
  %t73 = load ptr, ptr @g-def-stream, align 8
  store ptr %t73, ptr @g-out, align 8
  %t74 = load ptr, ptr %f.addr.5, align 8
  call void @emit-defn(ptr %t74)
  br label %cond.end5
cond.test5.7:
  %t75 = load ptr, ptr %h.addr.30, align 8
  %t76 = getelementptr inbounds [13 x i8], ptr @.str.606, i64 0, i64 0
  %t77 = call i32 @strcmp(ptr %t75, ptr %t76)
  %t78 = icmp eq i32 %t77, 0
  br i1 %t78, label %cond.then5.7, label %cond.test5.8
cond.then5.7:
  %t79 = load ptr, ptr %f.addr.5, align 8
  call void @emit-compile-time(ptr %t79)
  br label %cond.end5
cond.test5.8:
  %t80 = load ptr, ptr %h.addr.30, align 8
  %t81 = getelementptr inbounds [9 x i8], ptr @.str.607, i64 0, i64 0
  %t82 = call i32 @strcmp(ptr %t80, ptr %t81)
  %t83 = icmp eq i32 %t82, 0
  br i1 %t83, label %cond.then5.8, label %cond.test5.9
cond.then5.8:
  %t84 = load ptr, ptr %f.addr.5, align 8
  call void @emit-defmacro(ptr %t84)
  br label %cond.end5
cond.test5.9:
  %t85 = load ptr, ptr %h.addr.30, align 8
  %t86 = getelementptr inbounds [11 x i8], ptr @.str.608, i64 0, i64 0
  %t87 = call i32 @strcmp(ptr %t85, ptr %t86)
  %t88 = icmp eq i32 %t87, 0
  br i1 %t88, label %cond.then5.9, label %cond.test5.10
cond.then5.9:
  %t89 = load ptr, ptr %f.addr.5, align 8
  call void @emit-def-rmacro(ptr %t89)
  br label %cond.end5
cond.test5.10:
  %t90 = load ptr, ptr %h.addr.30, align 8
  %t91 = getelementptr inbounds [7 x i8], ptr @.str.609, i64 0, i64 0
  %t92 = call i32 @strcmp(ptr %t90, ptr %t91)
  %t93 = icmp eq i32 %t92, 0
  br i1 %t93, label %cond.then5.10, label %cond.test5.11
cond.then5.10:
  %t94 = load ptr, ptr %f.addr.5, align 8
  call void @emit-import(ptr %t94)
  br label %cond.end5
cond.test5.11:
  %t95 = load ptr, ptr %h.addr.30, align 8
  %t96 = getelementptr inbounds [8 x i8], ptr @.str.610, i64 0, i64 0
  %t97 = call i32 @strcmp(ptr %t95, ptr %t96)
  %t98 = icmp eq i32 %t97, 0
  br i1 %t98, label %cond.then5.11, label %cond.test5.12
cond.then5.11:
  %t99 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t99, ptr @g-out, align 8
  %t100 = load ptr, ptr %f.addr.5, align 8
  call void @emit-nuch-declare-import(ptr %t100)
  br label %cond.end5
cond.test5.12:
  br i1 1, label %cond.then5.12, label %cond.end5
cond.then5.12:
  %t101 = load ptr, ptr %f.addr.5, align 8
  %t102 = getelementptr inbounds %Node, ptr %t101, i32 0, i32 1
  %t103 = load i32, ptr %t102, align 4
  %t104 = getelementptr inbounds [27 x i8], ptr @.str.611, i64 0, i64 0
  %t105 = load ptr, ptr %h.addr.30, align 8
  %t106 = call ptr @fmt-s(ptr %t104, ptr %t105)
  call void @die-at(i32 %t103, ptr %t106)
  br label %cond.end5
cond.end5:
  %t107 = load ptr, ptr %fc.addr.1, align 8
  %t108 = getelementptr inbounds %Node, ptr %t107, i32 0, i32 5
  %t109 = load ptr, ptr %t108, align 8
  store ptr %t109, ptr %fc.addr.1, align 8
  br label %while.cond0
while.end0:
  ret void
}

define i32 @import-list-has(ptr %list.arg, ptr %path.arg) {
entry:
  %list.addr = alloca ptr, align 8
  store ptr %list.arg, ptr %list.addr, align 8
  %path.addr = alloca ptr, align 8
  store ptr %path.arg, ptr %path.addr, align 8
  %cur.addr.0 = alloca ptr, align 8
  %entry.addr.4 = alloca ptr, align 8
  %t1 = load ptr, ptr %list.addr, align 8
  store ptr %t1, ptr %cur.addr.0, align 8
  br label %while.cond0
while.cond0:
  %t2 = load ptr, ptr %cur.addr.0, align 8
  %t3 = icmp ne ptr %t2, null
  br i1 %t3, label %while.body0, label %while.end0
while.body0:
  %t5 = load ptr, ptr %cur.addr.0, align 8
  store ptr %t5, ptr %entry.addr.4, align 8
  %t6 = load ptr, ptr %entry.addr.4, align 8
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 3
  %t8 = load ptr, ptr %t7, align 8
  %t9 = load ptr, ptr %path.addr, align 8
  %t10 = call i32 @strcmp(ptr %t8, ptr %t9)
  %t11 = icmp eq i32 %t10, 0
  br i1 %t11, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret i32 1
cond.end1:
  %t12 = load ptr, ptr %entry.addr.4, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 5
  %t14 = load ptr, ptr %t13, align 8
  store ptr %t14, ptr %cur.addr.0, align 8
  br label %while.cond0
while.end0:
  ret i32 0
}

define ptr @import-list-push(ptr %list.arg, ptr %path.arg) {
entry:
  %list.addr = alloca ptr, align 8
  store ptr %list.arg, ptr %list.addr, align 8
  %path.addr = alloca ptr, align 8
  store ptr %path.arg, ptr %path.addr, align 8
  %n.addr.0 = alloca ptr, align 8
  %t1 = getelementptr %Node, ptr null, i32 1
  %t2 = ptrtoint ptr %t1 to i64
  %t3 = call ptr @arena-alloc(i64 %t2)
  store ptr %t3, ptr %n.addr.0, align 8
  %t4 = load ptr, ptr %n.addr.0, align 8
  %t5 = getelementptr inbounds %Node, ptr %t4, i32 0, i32 0
  store i32 1, ptr %t5, align 4
  %t6 = load ptr, ptr %n.addr.0, align 8
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 1
  store i32 0, ptr %t7, align 4
  %t8 = load ptr, ptr %n.addr.0, align 8
  %t9 = sext i32 0 to i64
  %t10 = getelementptr inbounds %Node, ptr %t8, i32 0, i32 2
  store i64 %t9, ptr %t10, align 8
  %t11 = load ptr, ptr %n.addr.0, align 8
  %t12 = load ptr, ptr %path.addr, align 8
  %t13 = getelementptr inbounds %Node, ptr %t11, i32 0, i32 3
  store ptr %t12, ptr %t13, align 8
  %t14 = load ptr, ptr %n.addr.0, align 8
  %t15 = getelementptr inbounds %Node, ptr %t14, i32 0, i32 4
  store ptr null, ptr %t15, align 8
  %t16 = load ptr, ptr %n.addr.0, align 8
  %t17 = load ptr, ptr %list.addr, align 8
  %t18 = getelementptr inbounds %Node, ptr %t16, i32 0, i32 5
  store ptr %t17, ptr %t18, align 8
  %t19 = load ptr, ptr %n.addr.0, align 8
  ret ptr %t19
}

define ptr @import-list-pop(ptr %list.arg) {
entry:
  %list.addr = alloca ptr, align 8
  store ptr %list.arg, ptr %list.addr, align 8
  %t0 = load ptr, ptr %list.addr, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret ptr null
cond.end0:
  %t2 = load ptr, ptr %list.addr, align 8
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 5
  %t4 = load ptr, ptr %t3, align 8
  ret ptr %t4
}

define i32 @file-exists(ptr %path.arg) {
entry:
  %path.addr = alloca ptr, align 8
  store ptr %path.arg, ptr %path.addr, align 8
  %f.addr.0 = alloca ptr, align 8
  %t1 = load ptr, ptr %path.addr, align 8
  %t2 = getelementptr inbounds [2 x i8], ptr @.str.612, i64 0, i64 0
  %t3 = call ptr @fopen(ptr %t1, ptr %t2)
  store ptr %t3, ptr %f.addr.0, align 8
  %t4 = load ptr, ptr %f.addr.0, align 8
  %t5 = icmp eq ptr %t4, null
  br i1 %t5, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret i32 0
cond.end0:
  %t6 = load ptr, ptr %f.addr.0, align 8
  %t7 = call i32 @fclose(ptr %t6)
  ret i32 1
}

define ptr @try-import-path(ptr %filename.arg) {
entry:
  %filename.addr = alloca ptr, align 8
  store ptr %filename.arg, ptr %filename.addr, align 8
  %pathlen.addr.0 = alloca i64, align 8
  %last-slash.addr.3 = alloca i64, align 8
  %i.addr.5 = alloca i64, align 8
  %dir.addr.21 = alloca ptr, align 8
  %candidate.addr.25 = alloca ptr, align 8
  %candidate.addr.34 = alloca ptr, align 8
  %j.addr.42 = alloca i32, align 4
  %candidate.addr.46 = alloca ptr, align 8
  %t1 = load ptr, ptr @g-source-path, align 8
  %t2 = call i64 @strlen(ptr %t1)
  store i64 %t2, ptr %pathlen.addr.0, align 8
  %t4 = sext i32 -1 to i64
  store i64 %t4, ptr %last-slash.addr.3, align 8
  %t6 = sext i32 0 to i64
  store i64 %t6, ptr %i.addr.5, align 8
  br label %while.cond0
while.cond0:
  %t7 = load i64, ptr %i.addr.5, align 8
  %t8 = load i64, ptr %pathlen.addr.0, align 8
  %t9 = icmp slt i64 %t7, %t8
  br i1 %t9, label %while.body0, label %while.end0
while.body0:
  %t10 = load ptr, ptr @g-source-path, align 8
  %t11 = load i64, ptr %i.addr.5, align 8
  %t12 = call i32 @char-at(ptr %t10, i64 %t11)
  %t13 = icmp eq i32 %t12, 47
  br i1 %t13, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t14 = load i64, ptr %i.addr.5, align 8
  store i64 %t14, ptr %last-slash.addr.3, align 8
  br label %cond.end1
cond.end1:
  %t15 = load i64, ptr %i.addr.5, align 8
  %t16 = sext i32 1 to i64
  %t17 = add nsw i64 %t15, %t16
  store i64 %t17, ptr %i.addr.5, align 8
  br label %while.cond0
while.end0:
  %t18 = load i64, ptr %last-slash.addr.3, align 8
  %t19 = sext i32 0 to i64
  %t20 = icmp sge i64 %t18, %t19
  br i1 %t20, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t22 = load ptr, ptr @g-source-path, align 8
  %t23 = load i64, ptr %last-slash.addr.3, align 8
  %t24 = call ptr @strndup(ptr %t22, i64 %t23)
  store ptr %t24, ptr %dir.addr.21, align 8
  %t26 = getelementptr inbounds [6 x i8], ptr @.str.613, i64 0, i64 0
  %t27 = load ptr, ptr %dir.addr.21, align 8
  %t28 = load ptr, ptr %filename.addr, align 8
  %t29 = call ptr @fmt-2s(ptr %t26, ptr %t27, ptr %t28)
  store ptr %t29, ptr %candidate.addr.25, align 8
  %t30 = load ptr, ptr %candidate.addr.25, align 8
  %t31 = call i32 @file-exists(ptr %t30)
  %t32 = icmp ne i32 %t31, 0
  br i1 %t32, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t33 = load ptr, ptr %candidate.addr.25, align 8
  ret ptr %t33
cond.end3:
  br label %cond.end2
cond.end2:
  %t35 = getelementptr inbounds [7 x i8], ptr @.str.614, i64 0, i64 0
  %t36 = load ptr, ptr %filename.addr, align 8
  %t37 = call ptr @fmt-s(ptr %t35, ptr %t36)
  store ptr %t37, ptr %candidate.addr.34, align 8
  %t38 = load ptr, ptr %candidate.addr.34, align 8
  %t39 = call i32 @file-exists(ptr %t38)
  %t40 = icmp ne i32 %t39, 0
  br i1 %t40, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t41 = load ptr, ptr %candidate.addr.34, align 8
  ret ptr %t41
cond.end4:
  store i32 0, ptr %j.addr.42, align 4
  br label %while.cond5
while.cond5:
  %t43 = load i32, ptr %j.addr.42, align 4
  %t44 = load i32, ptr @g-num-include-paths, align 4
  %t45 = icmp slt i32 %t43, %t44
  br i1 %t45, label %while.body5, label %while.end5
while.body5:
  %t47 = getelementptr inbounds [6 x i8], ptr @.str.615, i64 0, i64 0
  %t48 = load ptr, ptr @g-include-paths, align 8
  %t49 = load i32, ptr %j.addr.42, align 4
  %t50 = sext i32 %t49 to i64
  %t51 = getelementptr inbounds ptr, ptr %t48, i64 %t50
  %t52 = load ptr, ptr %t51, align 8
  %t53 = load ptr, ptr %filename.addr, align 8
  %t54 = call ptr @fmt-2s(ptr %t47, ptr %t52, ptr %t53)
  store ptr %t54, ptr %candidate.addr.46, align 8
  %t55 = load ptr, ptr %candidate.addr.46, align 8
  %t56 = call i32 @file-exists(ptr %t55)
  %t57 = icmp ne i32 %t56, 0
  br i1 %t57, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t58 = load ptr, ptr %candidate.addr.46, align 8
  ret ptr %t58
cond.end6:
  %t59 = load i32, ptr %j.addr.42, align 4
  %t60 = add nsw i32 %t59, 1
  store i32 %t60, ptr %j.addr.42, align 4
  br label %while.cond5
while.end5:
  ret ptr null
}

define ptr @resolve-import(ptr %name.arg, i32 %line.arg) {
entry:
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %nuc-path.addr.0 = alloca ptr, align 8
  %nuch-path.addr.8 = alloca ptr, align 8
  %t1 = getelementptr inbounds [7 x i8], ptr @.str.616, i64 0, i64 0
  %t2 = load ptr, ptr %name.addr, align 8
  %t3 = call ptr @fmt-s(ptr %t1, ptr %t2)
  %t4 = call ptr @try-import-path(ptr %t3)
  store ptr %t4, ptr %nuc-path.addr.0, align 8
  %t5 = load ptr, ptr %nuc-path.addr.0, align 8
  %t6 = icmp ne ptr %t5, null
  br i1 %t6, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t7 = load ptr, ptr %nuc-path.addr.0, align 8
  ret ptr %t7
cond.end0:
  %t9 = getelementptr inbounds [8 x i8], ptr @.str.617, i64 0, i64 0
  %t10 = load ptr, ptr %name.addr, align 8
  %t11 = call ptr @fmt-s(ptr %t9, ptr %t10)
  %t12 = call ptr @try-import-path(ptr %t11)
  store ptr %t12, ptr %nuch-path.addr.8, align 8
  %t13 = load ptr, ptr %nuch-path.addr.8, align 8
  %t14 = icmp ne ptr %t13, null
  br i1 %t14, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t15 = load ptr, ptr %nuch-path.addr.8, align 8
  ret ptr %t15
cond.end1:
  ret ptr null
}

define void @emit-import(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %ff.addr.0 = alloca ptr, align 8
  %name-node.addr.9 = alloca ptr, align 8
  %name.addr.31 = alloca ptr, align 8
  %path.addr.35 = alloca ptr, align 8
  %save-src.addr.63 = alloca ptr, align 8
  %save-pos.addr.65 = alloca i64, align 8
  %save-line.addr.67 = alloca i32, align 4
  %save-path.addr.69 = alloca ptr, align 8
  %save-peek.addr.71 = alloca ptr, align 8
  %save-peek-valid.addr.73 = alloca i32, align 4
  %src.addr.78 = alloca ptr, align 8
  %forms.addr.84 = alloca ptr, align 8
  %is-nuch.addr.87 = alloca i32, align 4
  %t1 = load ptr, ptr %form.addr, align 8
  store ptr %t1, ptr %ff.addr.0, align 8
  %t2 = load ptr, ptr %form.addr, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp ne i32 %t3, 2
  br i1 %t4, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t5 = load ptr, ptr %ff.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 1
  %t7 = load i32, ptr %t6, align 4
  %t8 = getelementptr inbounds [31 x i8], ptr @.str.618, i64 0, i64 0
  call void @die-at(i32 %t7, ptr %t8)
  br label %cond.end0
cond.end0:
  %t10 = load ptr, ptr %form.addr, align 8
  %t11 = call ptr @node-at(ptr %t10, i32 1)
  store ptr %t11, ptr %name-node.addr.9, align 8
  %t12 = load ptr, ptr %name-node.addr.9, align 8
  %t13 = getelementptr inbounds %Node, ptr %t12, i32 0, i32 0
  %t14 = load i32, ptr %t13, align 4
  %t15 = icmp eq i32 %t14, 1
  br i1 %t15, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t16 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t16, ptr @g-out, align 8
  %t17 = load ptr, ptr %name-node.addr.9, align 8
  %t18 = getelementptr inbounds %Node, ptr %t17, i32 0, i32 3
  %t19 = load ptr, ptr %t18, align 8
  %t20 = load ptr, ptr %ff.addr.0, align 8
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 1
  %t22 = load i32, ptr %t21, align 4
  call void @emit-c-include(ptr %t19, i32 %t22)
  ret void
cond.end1:
  %t23 = load ptr, ptr %name-node.addr.9, align 8
  %t24 = getelementptr inbounds %Node, ptr %t23, i32 0, i32 0
  %t25 = load i32, ptr %t24, align 4
  %t26 = icmp ne i32 %t25, 2
  br i1 %t26, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t27 = load ptr, ptr %ff.addr.0, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 1
  %t29 = load i32, ptr %t28, align 4
  %t30 = getelementptr inbounds [30 x i8], ptr @.str.619, i64 0, i64 0
  call void @die-at(i32 %t29, ptr %t30)
  br label %cond.end2
cond.end2:
  %t32 = load ptr, ptr %name-node.addr.9, align 8
  %t33 = getelementptr inbounds %Node, ptr %t32, i32 0, i32 3
  %t34 = load ptr, ptr %t33, align 8
  store ptr %t34, ptr %name.addr.31, align 8
  %t36 = load ptr, ptr %name.addr.31, align 8
  %t37 = load ptr, ptr %ff.addr.0, align 8
  %t38 = getelementptr inbounds %Node, ptr %t37, i32 0, i32 1
  %t39 = load i32, ptr %t38, align 4
  %t40 = call ptr @resolve-import(ptr %t36, i32 %t39)
  store ptr %t40, ptr %path.addr.35, align 8
  %t41 = load ptr, ptr %path.addr.35, align 8
  %t42 = icmp eq ptr %t41, null
  br i1 %t42, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t43 = load ptr, ptr %ff.addr.0, align 8
  %t44 = getelementptr inbounds %Node, ptr %t43, i32 0, i32 1
  %t45 = load i32, ptr %t44, align 4
  %t46 = getelementptr inbounds [25 x i8], ptr @.str.620, i64 0, i64 0
  %t47 = load ptr, ptr %name.addr.31, align 8
  %t48 = call ptr @fmt-s(ptr %t46, ptr %t47)
  call void @die-at(i32 %t45, ptr %t48)
  br label %cond.end3
cond.end3:
  %t49 = load ptr, ptr @g-imported, align 8
  %t50 = load ptr, ptr %path.addr.35, align 8
  %t51 = call i32 @import-list-has(ptr %t49, ptr %t50)
  %t52 = icmp ne i32 %t51, 0
  br i1 %t52, label %cond.then4.0, label %cond.end4
cond.then4.0:
  ret void
cond.end4:
  %t53 = load ptr, ptr @g-importing, align 8
  %t54 = load ptr, ptr %path.addr.35, align 8
  %t55 = call i32 @import-list-has(ptr %t53, ptr %t54)
  %t56 = icmp ne i32 %t55, 0
  br i1 %t56, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t57 = load ptr, ptr %ff.addr.0, align 8
  %t58 = getelementptr inbounds %Node, ptr %t57, i32 0, i32 1
  %t59 = load i32, ptr %t58, align 4
  %t60 = getelementptr inbounds [32 x i8], ptr @.str.621, i64 0, i64 0
  %t61 = load ptr, ptr %name.addr.31, align 8
  %t62 = call ptr @fmt-s(ptr %t60, ptr %t61)
  call void @die-at(i32 %t59, ptr %t62)
  br label %cond.end5
cond.end5:
  %t64 = load ptr, ptr @g-src, align 8
  store ptr %t64, ptr %save-src.addr.63, align 8
  %t66 = load i64, ptr @g-pos, align 8
  store i64 %t66, ptr %save-pos.addr.65, align 8
  %t68 = load i32, ptr @g-line, align 4
  store i32 %t68, ptr %save-line.addr.67, align 4
  %t70 = load ptr, ptr @g-source-path, align 8
  store ptr %t70, ptr %save-path.addr.69, align 8
  %t72 = load ptr, ptr @g-peek, align 8
  store ptr %t72, ptr %save-peek.addr.71, align 8
  %t74 = load i32, ptr @g-peek-valid, align 4
  store i32 %t74, ptr %save-peek-valid.addr.73, align 4
  %t75 = load ptr, ptr @g-importing, align 8
  %t76 = load ptr, ptr %path.addr.35, align 8
  %t77 = call ptr @import-list-push(ptr %t75, ptr %t76)
  store ptr %t77, ptr @g-importing, align 8
  %t79 = load ptr, ptr %path.addr.35, align 8
  %t80 = call ptr @read-file(ptr %t79)
  store ptr %t80, ptr %src.addr.78, align 8
  %t81 = load ptr, ptr %path.addr.35, align 8
  store ptr %t81, ptr @g-source-path, align 8
  %t82 = load ptr, ptr %src.addr.78, align 8
  store ptr %t82, ptr @g-src, align 8
  %t83 = sext i32 0 to i64
  store i64 %t83, ptr @g-pos, align 8
  store i32 1, ptr @g-line, align 4
  store i32 0, ptr @g-peek-valid, align 4
  %t85 = call ptr @read-program()
  %t86 = call ptr @desugar(ptr %t85)
  store ptr %t86, ptr %forms.addr.84, align 8
  %t88 = load ptr, ptr %path.addr.35, align 8
  %t89 = getelementptr inbounds [6 x i8], ptr @.str.622, i64 0, i64 0
  %t90 = call i32 @str-ends-with(ptr %t88, ptr %t89)
  store i32 %t90, ptr %is-nuch.addr.87, align 4
  %t91 = load i32, ptr %is-nuch.addr.87, align 4
  %t92 = icmp ne i32 %t91, 0
  br i1 %t92, label %cond.then6.0, label %cond.test6.1
cond.then6.0:
  %t93 = load ptr, ptr %forms.addr.84, align 8
  call void @emit-nuch-import-forms(ptr %t93)
  br label %cond.end6
cond.test6.1:
  br i1 1, label %cond.then6.1, label %cond.end6
cond.then6.1:
  %t94 = load ptr, ptr %forms.addr.84, align 8
  call void @emit-toplevel-forms(ptr %t94)
  br label %cond.end6
cond.end6:
  %t95 = load ptr, ptr %src.addr.78, align 8
  call void @free(ptr %t95)
  %t96 = load ptr, ptr @g-importing, align 8
  %t97 = call ptr @import-list-pop(ptr %t96)
  store ptr %t97, ptr @g-importing, align 8
  %t98 = load ptr, ptr @g-imported, align 8
  %t99 = load ptr, ptr %path.addr.35, align 8
  %t100 = call ptr @import-list-push(ptr %t98, ptr %t99)
  store ptr %t100, ptr @g-imported, align 8
  %t101 = load ptr, ptr %save-path.addr.69, align 8
  store ptr %t101, ptr @g-source-path, align 8
  %t102 = load ptr, ptr %save-src.addr.63, align 8
  store ptr %t102, ptr @g-src, align 8
  %t103 = load i64, ptr %save-pos.addr.65, align 8
  store i64 %t103, ptr @g-pos, align 8
  %t104 = load i32, ptr %save-line.addr.67, align 4
  store i32 %t104, ptr @g-line, align 4
  %t105 = load ptr, ptr %save-peek.addr.71, align 8
  store ptr %t105, ptr @g-peek, align 8
  %t106 = load i32, ptr %save-peek-valid.addr.73, align 4
  store i32 %t106, ptr @g-peek-valid, align 4
  ret void
}

define ptr @type-name-to-c(ptr %name.arg) {
entry:
  %name.addr = alloca ptr, align 8
  store ptr %name.arg, ptr %name.addr, align 8
  %t0 = load ptr, ptr %name.addr, align 8
  %t1 = getelementptr inbounds [5 x i8], ptr @.str.623, i64 0, i64 0
  %t2 = call i32 @strcmp(ptr %t0, ptr %t1)
  %t3 = icmp eq i32 %t2, 0
  br i1 %t3, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t4 = getelementptr inbounds [5 x i8], ptr @.str.624, i64 0, i64 0
  ret ptr %t4
cond.end0:
  %t5 = load ptr, ptr %name.addr, align 8
  %t6 = getelementptr inbounds [3 x i8], ptr @.str.625, i64 0, i64 0
  %t7 = call i32 @strcmp(ptr %t5, ptr %t6)
  %t8 = icmp eq i32 %t7, 0
  br i1 %t8, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t9 = getelementptr inbounds [6 x i8], ptr @.str.626, i64 0, i64 0
  ret ptr %t9
cond.end1:
  %t10 = load ptr, ptr %name.addr, align 8
  %t11 = getelementptr inbounds [3 x i8], ptr @.str.627, i64 0, i64 0
  %t12 = call i32 @strcmp(ptr %t10, ptr %t11)
  %t13 = icmp eq i32 %t12, 0
  br i1 %t13, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t14 = getelementptr inbounds [7 x i8], ptr @.str.628, i64 0, i64 0
  ret ptr %t14
cond.end2:
  %t15 = load ptr, ptr %name.addr, align 8
  %t16 = getelementptr inbounds [4 x i8], ptr @.str.629, i64 0, i64 0
  %t17 = call i32 @strcmp(ptr %t15, ptr %t16)
  %t18 = icmp eq i32 %t17, 0
  br i1 %t18, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t19 = getelementptr inbounds [8 x i8], ptr @.str.630, i64 0, i64 0
  ret ptr %t19
cond.end3:
  %t20 = load ptr, ptr %name.addr, align 8
  %t21 = getelementptr inbounds [4 x i8], ptr @.str.631, i64 0, i64 0
  %t22 = call i32 @strcmp(ptr %t20, ptr %t21)
  %t23 = icmp eq i32 %t22, 0
  br i1 %t23, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t24 = getelementptr inbounds [8 x i8], ptr @.str.632, i64 0, i64 0
  ret ptr %t24
cond.end4:
  %t25 = load ptr, ptr %name.addr, align 8
  %t26 = getelementptr inbounds [4 x i8], ptr @.str.633, i64 0, i64 0
  %t27 = call i32 @strcmp(ptr %t25, ptr %t26)
  %t28 = icmp eq i32 %t27, 0
  br i1 %t28, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t29 = getelementptr inbounds [8 x i8], ptr @.str.634, i64 0, i64 0
  ret ptr %t29
cond.end5:
  %t30 = load ptr, ptr %name.addr, align 8
  %t31 = getelementptr inbounds [4 x i8], ptr @.str.635, i64 0, i64 0
  %t32 = call i32 @strcmp(ptr %t30, ptr %t31)
  %t33 = icmp eq i32 %t32, 0
  br i1 %t33, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t34 = getelementptr inbounds [8 x i8], ptr @.str.636, i64 0, i64 0
  ret ptr %t34
cond.end6:
  %t35 = load ptr, ptr %name.addr, align 8
  %t36 = getelementptr inbounds [4 x i8], ptr @.str.637, i64 0, i64 0
  %t37 = call i32 @strcmp(ptr %t35, ptr %t36)
  %t38 = icmp eq i32 %t37, 0
  br i1 %t38, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t39 = getelementptr inbounds [8 x i8], ptr @.str.638, i64 0, i64 0
  ret ptr %t39
cond.end7:
  %t40 = load ptr, ptr %name.addr, align 8
  %t41 = getelementptr inbounds [5 x i8], ptr @.str.639, i64 0, i64 0
  %t42 = call i32 @strcmp(ptr %t40, ptr %t41)
  %t43 = icmp eq i32 %t42, 0
  br i1 %t43, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t44 = getelementptr inbounds [9 x i8], ptr @.str.640, i64 0, i64 0
  ret ptr %t44
cond.end8:
  %t45 = load ptr, ptr %name.addr, align 8
  %t46 = getelementptr inbounds [5 x i8], ptr @.str.641, i64 0, i64 0
  %t47 = call i32 @strcmp(ptr %t45, ptr %t46)
  %t48 = icmp eq i32 %t47, 0
  br i1 %t48, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t49 = getelementptr inbounds [9 x i8], ptr @.str.642, i64 0, i64 0
  ret ptr %t49
cond.end9:
  %t50 = load ptr, ptr %name.addr, align 8
  %t51 = getelementptr inbounds [5 x i8], ptr @.str.643, i64 0, i64 0
  %t52 = call i32 @strcmp(ptr %t50, ptr %t51)
  %t53 = icmp eq i32 %t52, 0
  br i1 %t53, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t54 = getelementptr inbounds [9 x i8], ptr @.str.644, i64 0, i64 0
  ret ptr %t54
cond.end10:
  %t55 = load ptr, ptr %name.addr, align 8
  %t56 = getelementptr inbounds [4 x i8], ptr @.str.645, i64 0, i64 0
  %t57 = call i32 @strcmp(ptr %t55, ptr %t56)
  %t58 = icmp eq i32 %t57, 0
  br i1 %t58, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t59 = getelementptr inbounds [6 x i8], ptr @.str.646, i64 0, i64 0
  ret ptr %t59
cond.end11:
  %t60 = load ptr, ptr %name.addr, align 8
  %t61 = sext i32 0 to i64
  %t62 = call i32 @char-at(ptr %t60, i64 %t61)
  %t63 = icmp eq i32 %t62, 42
  br i1 %t63, label %cond.then12.0, label %cond.end12
cond.then12.0:
  %t64 = getelementptr inbounds [4 x i8], ptr @.str.647, i64 0, i64 0
  %t65 = load ptr, ptr %name.addr, align 8
  %t66 = sext i32 1 to i64
  %t67 = getelementptr inbounds i8, ptr %t65, i64 %t66
  %t68 = call ptr @type-name-to-c(ptr %t67)
  %t69 = call ptr @fmt-s(ptr %t64, ptr %t68)
  ret ptr %t69
cond.end12:
  %t70 = getelementptr inbounds [10 x i8], ptr @.str.648, i64 0, i64 0
  %t71 = load ptr, ptr %name.addr, align 8
  %t72 = call ptr @fmt-s(ptr %t70, ptr %t71)
  ret ptr %t72
}

define void @emit-cheader-defstruct(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %name.addr.0 = alloca ptr, align 8
  %nfields.addr.5 = alloca i32, align 4
  %i.addr.11 = alloca i32, align 4
  %field.addr.15 = alloca ptr, align 8
  %fname.addr.20 = alloca ptr, align 8
  %tname.addr.21 = alloca ptr, align 8
  %t1 = load ptr, ptr %form.addr, align 8
  %t2 = call ptr @node-at(ptr %t1, i32 1)
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 3
  %t4 = load ptr, ptr %t3, align 8
  store ptr %t4, ptr %name.addr.0, align 8
  %t6 = load ptr, ptr %form.addr, align 8
  %t7 = call i32 @node-len(ptr %t6)
  %t8 = sub nsw i32 %t7, 2
  store i32 %t8, ptr %nfields.addr.5, align 4
  %t9 = getelementptr inbounds [18 x i8], ptr @.str.649, i64 0, i64 0
  %t10 = call i32 (ptr, ...) @printf(ptr %t9)
  store i32 0, ptr %i.addr.11, align 4
  br label %while.cond0
while.cond0:
  %t12 = load i32, ptr %i.addr.11, align 4
  %t13 = load i32, ptr %nfields.addr.5, align 4
  %t14 = icmp slt i32 %t12, %t13
  br i1 %t14, label %while.body0, label %while.end0
while.body0:
  %t16 = load ptr, ptr %form.addr, align 8
  %t17 = load i32, ptr %i.addr.11, align 4
  %t18 = add nsw i32 %t17, 2
  %t19 = call ptr @node-at(ptr %t16, i32 %t18)
  store ptr %t19, ptr %field.addr.15, align 8
  store ptr null, ptr %fname.addr.20, align 8
  store ptr null, ptr %tname.addr.21, align 8
  %t22 = load ptr, ptr %field.addr.15, align 8
  call void @extract-name-type(ptr %t22, ptr %fname.addr.20, ptr %tname.addr.21)
  %t23 = load ptr, ptr %tname.addr.21, align 8
  %t24 = icmp ne ptr %t23, null
  br i1 %t24, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t25 = getelementptr inbounds [12 x i8], ptr @.str.650, i64 0, i64 0
  %t26 = load ptr, ptr %tname.addr.21, align 8
  %t27 = call ptr @type-name-to-c(ptr %t26)
  %t28 = load ptr, ptr %fname.addr.20, align 8
  %t29 = call i32 (ptr, ...) @printf(ptr %t25, ptr %t27, ptr %t28)
  br label %cond.end1
cond.end1:
  %t30 = load i32, ptr %i.addr.11, align 4
  %t31 = add nsw i32 %t30, 1
  store i32 %t31, ptr %i.addr.11, align 4
  br label %while.cond0
while.end0:
  %t32 = getelementptr inbounds [8 x i8], ptr @.str.651, i64 0, i64 0
  %t33 = load ptr, ptr %name.addr.0, align 8
  %t34 = call i32 (ptr, ...) @printf(ptr %t32, ptr %t33)
  ret void
}

define void @emit-cheader-declare(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %name-node.addr.0 = alloca ptr, align 8
  %fname.addr.3 = alloca ptr, align 8
  %ret-name.addr.4 = alloca ptr, align 8
  %params.addr.14 = alloca ptr, align 8
  %n.addr.17 = alloca i32, align 4
  %i.addr.20 = alloca i32, align 4
  %p.addr.32 = alloca ptr, align 8
  %pname.addr.36 = alloca ptr, align 8
  %ptname.addr.37 = alloca ptr, align 8
  %t1 = load ptr, ptr %form.addr, align 8
  %t2 = call ptr @node-at(ptr %t1, i32 1)
  store ptr %t2, ptr %name-node.addr.0, align 8
  store ptr null, ptr %fname.addr.3, align 8
  store ptr null, ptr %ret-name.addr.4, align 8
  %t5 = load ptr, ptr %name-node.addr.0, align 8
  call void @extract-name-type(ptr %t5, ptr %fname.addr.3, ptr %ret-name.addr.4)
  %t6 = load ptr, ptr %ret-name.addr.4, align 8
  %t7 = icmp eq ptr %t6, null
  br i1 %t7, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t8 = getelementptr inbounds [5 x i8], ptr @.str.652, i64 0, i64 0
  store ptr %t8, ptr %ret-name.addr.4, align 8
  br label %cond.end0
cond.end0:
  %t9 = getelementptr inbounds [7 x i8], ptr @.str.653, i64 0, i64 0
  %t10 = load ptr, ptr %ret-name.addr.4, align 8
  %t11 = call ptr @type-name-to-c(ptr %t10)
  %t12 = load ptr, ptr %fname.addr.3, align 8
  %t13 = call i32 (ptr, ...) @printf(ptr %t9, ptr %t11, ptr %t12)
  %t15 = load ptr, ptr %form.addr, align 8
  %t16 = call ptr @node-at(ptr %t15, i32 2)
  store ptr %t16, ptr %params.addr.14, align 8
  %t18 = load ptr, ptr %params.addr.14, align 8
  %t19 = call i32 @node-len(ptr %t18)
  store i32 %t19, ptr %n.addr.17, align 4
  store i32 0, ptr %i.addr.20, align 4
  %t21 = load i32, ptr %n.addr.17, align 4
  %t22 = icmp eq i32 %t21, 0
  br i1 %t22, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t23 = getelementptr inbounds [5 x i8], ptr @.str.654, i64 0, i64 0
  %t24 = call i32 (ptr, ...) @printf(ptr %t23)
  br label %cond.end1
cond.end1:
  br label %while.cond2
while.cond2:
  %t25 = load i32, ptr %i.addr.20, align 4
  %t26 = load i32, ptr %n.addr.17, align 4
  %t27 = icmp slt i32 %t25, %t26
  br i1 %t27, label %while.body2, label %while.end2
while.body2:
  %t28 = load i32, ptr %i.addr.20, align 4
  %t29 = icmp ne i32 %t28, 0
  br i1 %t29, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t30 = getelementptr inbounds [3 x i8], ptr @.str.655, i64 0, i64 0
  %t31 = call i32 (ptr, ...) @printf(ptr %t30)
  br label %cond.end3
cond.end3:
  %t33 = load ptr, ptr %params.addr.14, align 8
  %t34 = load i32, ptr %i.addr.20, align 4
  %t35 = call ptr @node-at(ptr %t33, i32 %t34)
  store ptr %t35, ptr %p.addr.32, align 8
  store ptr null, ptr %pname.addr.36, align 8
  store ptr null, ptr %ptname.addr.37, align 8
  %t38 = load ptr, ptr %p.addr.32, align 8
  call void @extract-name-type(ptr %t38, ptr %pname.addr.36, ptr %ptname.addr.37)
  %t39 = load ptr, ptr %ptname.addr.37, align 8
  %t40 = icmp ne ptr %t39, null
  br i1 %t40, label %cond.then4.0, label %cond.test4.1
cond.then4.0:
  %t41 = getelementptr inbounds [6 x i8], ptr @.str.656, i64 0, i64 0
  %t42 = load ptr, ptr %ptname.addr.37, align 8
  %t43 = call ptr @type-name-to-c(ptr %t42)
  %t44 = load ptr, ptr %pname.addr.36, align 8
  %t45 = call i32 (ptr, ...) @printf(ptr %t41, ptr %t43, ptr %t44)
  br label %cond.end4
cond.test4.1:
  br i1 1, label %cond.then4.1, label %cond.end4
cond.then4.1:
  %t46 = load ptr, ptr %pname.addr.36, align 8
  %t47 = icmp ne ptr %t46, null
  br i1 %t47, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t48 = getelementptr inbounds [9 x i8], ptr @.str.657, i64 0, i64 0
  %t49 = load ptr, ptr %pname.addr.36, align 8
  %t50 = call i32 (ptr, ...) @printf(ptr %t48, ptr %t49)
  br label %cond.end5
cond.end5:
  br label %cond.end4
cond.end4:
  %t51 = load i32, ptr %i.addr.20, align 4
  %t52 = add nsw i32 %t51, 1
  store i32 %t52, ptr %i.addr.20, align 4
  br label %while.cond2
while.end2:
  %t53 = getelementptr inbounds [4 x i8], ptr @.str.658, i64 0, i64 0
  %t54 = call i32 (ptr, ...) @printf(ptr %t53)
  ret void
}

define void @emit-cheader-defconst(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %name.addr.0 = alloca ptr, align 8
  %val-node.addr.5 = alloca ptr, align 8
  %t1 = load ptr, ptr %form.addr, align 8
  %t2 = call ptr @node-at(ptr %t1, i32 1)
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 3
  %t4 = load ptr, ptr %t3, align 8
  store ptr %t4, ptr %name.addr.0, align 8
  %t6 = load ptr, ptr %form.addr, align 8
  %t7 = call ptr @node-at(ptr %t6, i32 2)
  store ptr %t7, ptr %val-node.addr.5, align 8
  %t8 = load ptr, ptr %val-node.addr.5, align 8
  %t9 = getelementptr inbounds %Node, ptr %t8, i32 0, i32 0
  %t10 = load i32, ptr %t9, align 4
  %t11 = icmp eq i32 %t10, 0
  br i1 %t11, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t12 = getelementptr inbounds [16 x i8], ptr @.str.659, i64 0, i64 0
  %t13 = load ptr, ptr %name.addr.0, align 8
  %t14 = load ptr, ptr %val-node.addr.5, align 8
  %t15 = getelementptr inbounds %Node, ptr %t14, i32 0, i32 2
  %t16 = load i64, ptr %t15, align 8
  %t17 = call i32 (ptr, ...) @printf(ptr %t12, ptr %t13, i64 %t16)
  br label %cond.end0
cond.end0:
  %t18 = load ptr, ptr %val-node.addr.5, align 8
  %t19 = getelementptr inbounds %Node, ptr %t18, i32 0, i32 0
  %t20 = load i32, ptr %t19, align 4
  %t21 = icmp eq i32 %t20, 1
  br i1 %t21, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t22 = getelementptr inbounds [17 x i8], ptr @.str.660, i64 0, i64 0
  %t23 = load ptr, ptr %name.addr.0, align 8
  %t24 = load ptr, ptr %val-node.addr.5, align 8
  %t25 = getelementptr inbounds %Node, ptr %t24, i32 0, i32 3
  %t26 = load ptr, ptr %t25, align 8
  %t27 = call i32 (ptr, ...) @printf(ptr %t22, ptr %t23, ptr %t26)
  br label %cond.end1
cond.end1:
  ret void
}

define void @emit-cheader-defenum(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %name.addr.0 = alloca ptr, align 8
  %n.addr.5 = alloca i32, align 4
  %i.addr.12 = alloca i32, align 4
  %variant.addr.16 = alloca ptr, align 8
  %t1 = load ptr, ptr %form.addr, align 8
  %t2 = call ptr @node-at(ptr %t1, i32 1)
  %t3 = getelementptr inbounds %Node, ptr %t2, i32 0, i32 3
  %t4 = load ptr, ptr %t3, align 8
  store ptr %t4, ptr %name.addr.0, align 8
  %t6 = load ptr, ptr %form.addr, align 8
  %t7 = call i32 @node-len(ptr %t6)
  %t8 = sub nsw i32 %t7, 2
  store i32 %t8, ptr %n.addr.5, align 4
  %t9 = getelementptr inbounds [11 x i8], ptr @.str.661, i64 0, i64 0
  %t10 = load ptr, ptr %name.addr.0, align 8
  %t11 = call i32 (ptr, ...) @printf(ptr %t9, ptr %t10)
  store i32 0, ptr %i.addr.12, align 4
  br label %while.cond0
while.cond0:
  %t13 = load i32, ptr %i.addr.12, align 4
  %t14 = load i32, ptr %n.addr.5, align 4
  %t15 = icmp slt i32 %t13, %t14
  br i1 %t15, label %while.body0, label %while.end0
while.body0:
  %t17 = load ptr, ptr %form.addr, align 8
  %t18 = load i32, ptr %i.addr.12, align 4
  %t19 = add nsw i32 %t18, 2
  %t20 = call ptr @node-at(ptr %t17, i32 %t19)
  %t21 = getelementptr inbounds %Node, ptr %t20, i32 0, i32 3
  %t22 = load ptr, ptr %t21, align 8
  store ptr %t22, ptr %variant.addr.16, align 8
  %t23 = getelementptr inbounds [15 x i8], ptr @.str.662, i64 0, i64 0
  %t24 = load ptr, ptr %name.addr.0, align 8
  %t25 = load ptr, ptr %variant.addr.16, align 8
  %t26 = load i32, ptr %i.addr.12, align 4
  %t27 = call i32 (ptr, ...) @printf(ptr %t23, ptr %t24, ptr %t25, i32 %t26)
  %t28 = load i32, ptr %i.addr.12, align 4
  %t29 = load i32, ptr %n.addr.5, align 4
  %t30 = sub nsw i32 %t29, 1
  %t31 = icmp slt i32 %t28, %t30
  br i1 %t31, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t32 = getelementptr inbounds [2 x i8], ptr @.str.663, i64 0, i64 0
  %t33 = call i32 (ptr, ...) @printf(ptr %t32)
  br label %cond.end1
cond.end1:
  %t34 = getelementptr inbounds [2 x i8], ptr @.str.664, i64 0, i64 0
  %t35 = call i32 (ptr, ...) @printf(ptr %t34)
  %t36 = load i32, ptr %i.addr.12, align 4
  %t37 = add nsw i32 %t36, 1
  store i32 %t37, ptr %i.addr.12, align 4
  br label %while.cond0
while.end0:
  %t38 = getelementptr inbounds [5 x i8], ptr @.str.665, i64 0, i64 0
  %t39 = call i32 (ptr, ...) @printf(ptr %t38)
  ret void
}

define void @emit-cheader-header(ptr %forms.arg, ptr %source-file.arg) {
entry:
  %forms.addr = alloca ptr, align 8
  store ptr %forms.arg, ptr %forms.addr, align 8
  %source-file.addr = alloca ptr, align 8
  store ptr %source-file.arg, ptr %source-file.addr, align 8
  %fc.addr.9 = alloca ptr, align 8
  %f.addr.13 = alloca ptr, align 8
  %and.val2 = alloca i1, align 1
  %and.val3 = alloca i1, align 1
  %and.val4 = alloca i1, align 1
  %h.addr.34 = alloca ptr, align 8
  %t0 = getelementptr inbounds [14 x i8], ptr @.str.666, i64 0, i64 0
  %t1 = call i32 (ptr, ...) @printf(ptr %t0)
  %t2 = getelementptr inbounds [21 x i8], ptr @.str.667, i64 0, i64 0
  %t3 = call i32 (ptr, ...) @printf(ptr %t2)
  %t4 = getelementptr inbounds [23 x i8], ptr @.str.668, i64 0, i64 0
  %t5 = call i32 (ptr, ...) @printf(ptr %t4)
  %t6 = getelementptr inbounds [53 x i8], ptr @.str.669, i64 0, i64 0
  %t7 = load ptr, ptr %source-file.addr, align 8
  %t8 = call i32 (ptr, ...) @printf(ptr %t6, ptr %t7)
  %t10 = load ptr, ptr %forms.addr, align 8
  store ptr %t10, ptr %fc.addr.9, align 8
  br label %while.cond0
while.cond0:
  %t11 = load ptr, ptr %fc.addr.9, align 8
  %t12 = icmp ne ptr %t11, null
  br i1 %t12, label %while.body0, label %while.end0
while.body0:
  %t14 = load ptr, ptr %fc.addr.9, align 8
  %t15 = getelementptr inbounds %Node, ptr %t14, i32 0, i32 4
  %t16 = load ptr, ptr %t15, align 8
  store ptr %t16, ptr %f.addr.13, align 8
  %t17 = load ptr, ptr %f.addr.13, align 8
  %t18 = icmp ne ptr %t17, null
  store i1 %t18, ptr %and.val3, align 1
  br i1 %t18, label %and.rhs3, label %and.end3
and.rhs3:
  %t19 = load ptr, ptr %f.addr.13, align 8
  %t20 = getelementptr inbounds %Node, ptr %t19, i32 0, i32 0
  %t21 = load i32, ptr %t20, align 4
  %t22 = icmp eq i32 %t21, 3
  store i1 %t22, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t23 = load i1, ptr %and.val3, align 1
  store i1 %t23, ptr %and.val2, align 1
  br i1 %t23, label %and.rhs2, label %and.end2
and.rhs2:
  %t24 = load ptr, ptr %f.addr.13, align 8
  %t25 = call i32 @node-len(ptr %t24)
  %t26 = icmp sgt i32 %t25, 0
  store i1 %t26, ptr %and.val4, align 1
  br i1 %t26, label %and.rhs4, label %and.end4
and.rhs4:
  %t27 = load ptr, ptr %f.addr.13, align 8
  %t28 = call ptr @node-at(ptr %t27, i32 0)
  %t29 = getelementptr inbounds %Node, ptr %t28, i32 0, i32 0
  %t30 = load i32, ptr %t29, align 4
  %t31 = icmp eq i32 %t30, 2
  store i1 %t31, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t32 = load i1, ptr %and.val4, align 1
  store i1 %t32, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t33 = load i1, ptr %and.val2, align 1
  br i1 %t33, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t35 = load ptr, ptr %f.addr.13, align 8
  %t36 = call ptr @node-at(ptr %t35, i32 0)
  %t37 = getelementptr inbounds %Node, ptr %t36, i32 0, i32 3
  %t38 = load ptr, ptr %t37, align 8
  store ptr %t38, ptr %h.addr.34, align 8
  %t39 = load ptr, ptr %h.addr.34, align 8
  %t40 = getelementptr inbounds [10 x i8], ptr @.str.670, i64 0, i64 0
  %t41 = call i32 @strcmp(ptr %t39, ptr %t40)
  %t42 = icmp eq i32 %t41, 0
  br i1 %t42, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t43 = load ptr, ptr %f.addr.13, align 8
  call void @emit-cheader-defstruct(ptr %t43)
  br label %cond.end5
cond.test5.1:
  %t44 = load ptr, ptr %h.addr.34, align 8
  %t45 = getelementptr inbounds [5 x i8], ptr @.str.671, i64 0, i64 0
  %t46 = call i32 @strcmp(ptr %t44, ptr %t45)
  %t47 = icmp eq i32 %t46, 0
  br i1 %t47, label %cond.then5.1, label %cond.test5.2
cond.then5.1:
  %t48 = load ptr, ptr %f.addr.13, align 8
  call void @emit-cheader-declare(ptr %t48)
  br label %cond.end5
cond.test5.2:
  %t49 = load ptr, ptr %h.addr.34, align 8
  %t50 = getelementptr inbounds [9 x i8], ptr @.str.672, i64 0, i64 0
  %t51 = call i32 @strcmp(ptr %t49, ptr %t50)
  %t52 = icmp eq i32 %t51, 0
  br i1 %t52, label %cond.then5.2, label %cond.test5.3
cond.then5.2:
  %t53 = load ptr, ptr %f.addr.13, align 8
  call void @emit-cheader-defconst(ptr %t53)
  br label %cond.end5
cond.test5.3:
  %t54 = load ptr, ptr %h.addr.34, align 8
  %t55 = getelementptr inbounds [8 x i8], ptr @.str.673, i64 0, i64 0
  %t56 = call i32 @strcmp(ptr %t54, ptr %t55)
  %t57 = icmp eq i32 %t56, 0
  br i1 %t57, label %cond.then5.3, label %cond.test5.4
cond.then5.3:
  %t58 = load ptr, ptr %f.addr.13, align 8
  call void @emit-cheader-defenum(ptr %t58)
  br label %cond.end5
cond.test5.4:
  br i1 1, label %cond.then5.4, label %cond.end5
cond.then5.4:
  br label %cond.end5
cond.end5:
  br label %cond.end1
cond.end1:
  %t59 = load ptr, ptr %fc.addr.9, align 8
  %t60 = getelementptr inbounds %Node, ptr %t59, i32 0, i32 5
  %t61 = load ptr, ptr %t60, align 8
  store ptr %t61, ptr %fc.addr.9, align 8
  br label %while.cond0
while.end0:
  ret void
}

define void @emit-nuch-list(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %i.addr.0 = alloca i32, align 4
  %n.addr.1 = alloca i32, align 4
  store i32 0, ptr %i.addr.0, align 4
  %t2 = load ptr, ptr %form.addr, align 8
  %t3 = call i32 @node-len(ptr %t2)
  store i32 %t3, ptr %n.addr.1, align 4
  br label %while.cond0
while.cond0:
  %t4 = load i32, ptr %i.addr.0, align 4
  %t5 = load i32, ptr %n.addr.1, align 4
  %t6 = icmp slt i32 %t4, %t5
  br i1 %t6, label %while.body0, label %while.end0
while.body0:
  %t7 = load i32, ptr %i.addr.0, align 4
  %t8 = icmp ne i32 %t7, 0
  br i1 %t8, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t9 = load ptr, ptr @stdout, align 8
  %t10 = call i32 @fputc(i32 32, ptr %t9)
  br label %cond.end1
cond.end1:
  %t11 = load ptr, ptr %form.addr, align 8
  %t12 = load i32, ptr %i.addr.0, align 4
  %t13 = call ptr @node-at(ptr %t11, i32 %t12)
  call void @print-node(ptr %t13)
  %t14 = load i32, ptr %i.addr.0, align 4
  %t15 = add nsw i32 %t14, 1
  store i32 %t15, ptr %i.addr.0, align 4
  br label %while.cond0
while.end0:
  ret void
}

define void @emit-nuch-defstruct(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %i.addr.2 = alloca i32, align 4
  %n.addr.3 = alloca i32, align 4
  %t0 = getelementptr inbounds [12 x i8], ptr @.str.674, i64 0, i64 0
  %t1 = call i32 (ptr, ...) @printf(ptr %t0)
  store i32 1, ptr %i.addr.2, align 4
  %t4 = load ptr, ptr %form.addr, align 8
  %t5 = call i32 @node-len(ptr %t4)
  store i32 %t5, ptr %n.addr.3, align 4
  br label %while.cond0
while.cond0:
  %t6 = load i32, ptr %i.addr.2, align 4
  %t7 = load i32, ptr %n.addr.3, align 4
  %t8 = icmp slt i32 %t6, %t7
  br i1 %t8, label %while.body0, label %while.end0
while.body0:
  %t9 = load i32, ptr %i.addr.2, align 4
  %t10 = icmp ne i32 %t9, 1
  br i1 %t10, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t11 = load ptr, ptr @stdout, align 8
  %t12 = call i32 @fputc(i32 32, ptr %t11)
  br label %cond.end1
cond.end1:
  %t13 = load ptr, ptr %form.addr, align 8
  %t14 = load i32, ptr %i.addr.2, align 4
  %t15 = call ptr @node-at(ptr %t13, i32 %t14)
  call void @print-node(ptr %t15)
  %t16 = load i32, ptr %i.addr.2, align 4
  %t17 = add nsw i32 %t16, 1
  store i32 %t17, ptr %i.addr.2, align 4
  br label %while.cond0
while.end0:
  %t18 = getelementptr inbounds [3 x i8], ptr @.str.675, i64 0, i64 0
  %t19 = call i32 (ptr, ...) @printf(ptr %t18)
  ret void
}

define void @emit-nuch-declare(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %params.addr.6 = alloca ptr, align 8
  %i.addr.9 = alloca i32, align 4
  %n.addr.10 = alloca i32, align 4
  %t0 = getelementptr inbounds [10 x i8], ptr @.str.676, i64 0, i64 0
  %t1 = call i32 (ptr, ...) @printf(ptr %t0)
  %t2 = load ptr, ptr %form.addr, align 8
  %t3 = call ptr @node-at(ptr %t2, i32 1)
  call void @print-node(ptr %t3)
  %t4 = getelementptr inbounds [3 x i8], ptr @.str.677, i64 0, i64 0
  %t5 = call i32 (ptr, ...) @printf(ptr %t4)
  %t7 = load ptr, ptr %form.addr, align 8
  %t8 = call ptr @node-at(ptr %t7, i32 2)
  store ptr %t8, ptr %params.addr.6, align 8
  store i32 0, ptr %i.addr.9, align 4
  %t11 = load ptr, ptr %params.addr.6, align 8
  %t12 = call i32 @node-len(ptr %t11)
  store i32 %t12, ptr %n.addr.10, align 4
  br label %while.cond0
while.cond0:
  %t13 = load i32, ptr %i.addr.9, align 4
  %t14 = load i32, ptr %n.addr.10, align 4
  %t15 = icmp slt i32 %t13, %t14
  br i1 %t15, label %while.body0, label %while.end0
while.body0:
  %t16 = load i32, ptr %i.addr.9, align 4
  %t17 = icmp ne i32 %t16, 0
  br i1 %t17, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t18 = load ptr, ptr @stdout, align 8
  %t19 = call i32 @fputc(i32 32, ptr %t18)
  br label %cond.end1
cond.end1:
  %t20 = load ptr, ptr %params.addr.6, align 8
  %t21 = load i32, ptr %i.addr.9, align 4
  %t22 = call ptr @node-at(ptr %t20, i32 %t21)
  call void @print-node(ptr %t22)
  %t23 = load i32, ptr %i.addr.9, align 4
  %t24 = add nsw i32 %t23, 1
  store i32 %t24, ptr %i.addr.9, align 4
  br label %while.cond0
while.end0:
  %t25 = getelementptr inbounds [4 x i8], ptr @.str.678, i64 0, i64 0
  %t26 = call i32 (ptr, ...) @printf(ptr %t25)
  ret void
}

define void @emit-nuch-defconst(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %t0 = getelementptr inbounds [11 x i8], ptr @.str.679, i64 0, i64 0
  %t1 = call i32 (ptr, ...) @printf(ptr %t0)
  %t2 = load ptr, ptr %form.addr, align 8
  %t3 = call ptr @node-at(ptr %t2, i32 1)
  call void @print-node(ptr %t3)
  %t4 = getelementptr inbounds [2 x i8], ptr @.str.680, i64 0, i64 0
  %t5 = call i32 (ptr, ...) @printf(ptr %t4)
  %t6 = load ptr, ptr %form.addr, align 8
  %t7 = call ptr @node-at(ptr %t6, i32 2)
  call void @print-node(ptr %t7)
  %t8 = getelementptr inbounds [3 x i8], ptr @.str.681, i64 0, i64 0
  %t9 = call i32 (ptr, ...) @printf(ptr %t8)
  ret void
}

define void @emit-nuch-defenum(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %i.addr.2 = alloca i32, align 4
  %n.addr.3 = alloca i32, align 4
  %t0 = getelementptr inbounds [9 x i8], ptr @.str.682, i64 0, i64 0
  %t1 = call i32 (ptr, ...) @printf(ptr %t0)
  store i32 1, ptr %i.addr.2, align 4
  %t4 = load ptr, ptr %form.addr, align 8
  %t5 = call i32 @node-len(ptr %t4)
  store i32 %t5, ptr %n.addr.3, align 4
  br label %while.cond0
while.cond0:
  %t6 = load i32, ptr %i.addr.2, align 4
  %t7 = load i32, ptr %n.addr.3, align 4
  %t8 = icmp slt i32 %t6, %t7
  br i1 %t8, label %while.body0, label %while.end0
while.body0:
  %t9 = load ptr, ptr @stdout, align 8
  %t10 = call i32 @fputc(i32 32, ptr %t9)
  %t11 = load ptr, ptr %form.addr, align 8
  %t12 = load i32, ptr %i.addr.2, align 4
  %t13 = call ptr @node-at(ptr %t11, i32 %t12)
  call void @print-node(ptr %t13)
  %t14 = load i32, ptr %i.addr.2, align 4
  %t15 = add nsw i32 %t14, 1
  store i32 %t15, ptr %i.addr.2, align 4
  br label %while.cond0
while.end0:
  %t16 = getelementptr inbounds [3 x i8], ptr @.str.683, i64 0, i64 0
  %t17 = call i32 (ptr, ...) @printf(ptr %t16)
  ret void
}

define void @emit-nuch-defmacro(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %t0 = load ptr, ptr %form.addr, align 8
  call void @print-node(ptr %t0)
  %t1 = getelementptr inbounds [2 x i8], ptr @.str.684, i64 0, i64 0
  %t2 = call i32 (ptr, ...) @printf(ptr %t1)
  ret void
}

define void @emit-nuch-header(ptr %forms.arg, ptr %source-file.arg) {
entry:
  %forms.addr = alloca ptr, align 8
  store ptr %forms.arg, ptr %forms.addr, align 8
  %source-file.addr = alloca ptr, align 8
  store ptr %source-file.arg, ptr %source-file.addr, align 8
  %fc.addr.3 = alloca ptr, align 8
  %f.addr.7 = alloca ptr, align 8
  %and.val2 = alloca i1, align 1
  %and.val3 = alloca i1, align 1
  %and.val4 = alloca i1, align 1
  %h.addr.28 = alloca ptr, align 8
  %t0 = getelementptr inbounds [23 x i8], ptr @.str.685, i64 0, i64 0
  %t1 = load ptr, ptr %source-file.addr, align 8
  %t2 = call i32 (ptr, ...) @printf(ptr %t0, ptr %t1)
  %t4 = load ptr, ptr %forms.addr, align 8
  store ptr %t4, ptr %fc.addr.3, align 8
  br label %while.cond0
while.cond0:
  %t5 = load ptr, ptr %fc.addr.3, align 8
  %t6 = icmp ne ptr %t5, null
  br i1 %t6, label %while.body0, label %while.end0
while.body0:
  %t8 = load ptr, ptr %fc.addr.3, align 8
  %t9 = getelementptr inbounds %Node, ptr %t8, i32 0, i32 4
  %t10 = load ptr, ptr %t9, align 8
  store ptr %t10, ptr %f.addr.7, align 8
  %t11 = load ptr, ptr %f.addr.7, align 8
  %t12 = icmp ne ptr %t11, null
  store i1 %t12, ptr %and.val3, align 1
  br i1 %t12, label %and.rhs3, label %and.end3
and.rhs3:
  %t13 = load ptr, ptr %f.addr.7, align 8
  %t14 = getelementptr inbounds %Node, ptr %t13, i32 0, i32 0
  %t15 = load i32, ptr %t14, align 4
  %t16 = icmp eq i32 %t15, 3
  store i1 %t16, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t17 = load i1, ptr %and.val3, align 1
  store i1 %t17, ptr %and.val2, align 1
  br i1 %t17, label %and.rhs2, label %and.end2
and.rhs2:
  %t18 = load ptr, ptr %f.addr.7, align 8
  %t19 = call i32 @node-len(ptr %t18)
  %t20 = icmp sgt i32 %t19, 0
  store i1 %t20, ptr %and.val4, align 1
  br i1 %t20, label %and.rhs4, label %and.end4
and.rhs4:
  %t21 = load ptr, ptr %f.addr.7, align 8
  %t22 = call ptr @node-at(ptr %t21, i32 0)
  %t23 = getelementptr inbounds %Node, ptr %t22, i32 0, i32 0
  %t24 = load i32, ptr %t23, align 4
  %t25 = icmp eq i32 %t24, 2
  store i1 %t25, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t26 = load i1, ptr %and.val4, align 1
  store i1 %t26, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t27 = load i1, ptr %and.val2, align 1
  br i1 %t27, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t29 = load ptr, ptr %f.addr.7, align 8
  %t30 = call ptr @node-at(ptr %t29, i32 0)
  %t31 = getelementptr inbounds %Node, ptr %t30, i32 0, i32 3
  %t32 = load ptr, ptr %t31, align 8
  store ptr %t32, ptr %h.addr.28, align 8
  %t33 = load ptr, ptr %h.addr.28, align 8
  %t34 = getelementptr inbounds [10 x i8], ptr @.str.686, i64 0, i64 0
  %t35 = call i32 @strcmp(ptr %t33, ptr %t34)
  %t36 = icmp eq i32 %t35, 0
  br i1 %t36, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t37 = load ptr, ptr %f.addr.7, align 8
  call void @emit-nuch-defstruct(ptr %t37)
  br label %cond.end5
cond.test5.1:
  %t38 = load ptr, ptr %h.addr.28, align 8
  %t39 = getelementptr inbounds [5 x i8], ptr @.str.687, i64 0, i64 0
  %t40 = call i32 @strcmp(ptr %t38, ptr %t39)
  %t41 = icmp eq i32 %t40, 0
  br i1 %t41, label %cond.then5.1, label %cond.test5.2
cond.then5.1:
  %t42 = load ptr, ptr %f.addr.7, align 8
  call void @emit-nuch-declare(ptr %t42)
  br label %cond.end5
cond.test5.2:
  %t43 = load ptr, ptr %h.addr.28, align 8
  %t44 = getelementptr inbounds [9 x i8], ptr @.str.688, i64 0, i64 0
  %t45 = call i32 @strcmp(ptr %t43, ptr %t44)
  %t46 = icmp eq i32 %t45, 0
  br i1 %t46, label %cond.then5.2, label %cond.test5.3
cond.then5.2:
  %t47 = load ptr, ptr %f.addr.7, align 8
  call void @emit-nuch-defconst(ptr %t47)
  br label %cond.end5
cond.test5.3:
  %t48 = load ptr, ptr %h.addr.28, align 8
  %t49 = getelementptr inbounds [8 x i8], ptr @.str.689, i64 0, i64 0
  %t50 = call i32 @strcmp(ptr %t48, ptr %t49)
  %t51 = icmp eq i32 %t50, 0
  br i1 %t51, label %cond.then5.3, label %cond.test5.4
cond.then5.3:
  %t52 = load ptr, ptr %f.addr.7, align 8
  call void @emit-nuch-defenum(ptr %t52)
  br label %cond.end5
cond.test5.4:
  %t53 = load ptr, ptr %h.addr.28, align 8
  %t54 = getelementptr inbounds [9 x i8], ptr @.str.690, i64 0, i64 0
  %t55 = call i32 @strcmp(ptr %t53, ptr %t54)
  %t56 = icmp eq i32 %t55, 0
  br i1 %t56, label %cond.then5.4, label %cond.test5.5
cond.then5.4:
  %t57 = load ptr, ptr %f.addr.7, align 8
  call void @emit-nuch-defmacro(ptr %t57)
  br label %cond.end5
cond.test5.5:
  br i1 1, label %cond.then5.5, label %cond.end5
cond.then5.5:
  br label %cond.end5
cond.end5:
  br label %cond.end1
cond.end1:
  %t58 = load ptr, ptr %fc.addr.3, align 8
  %t59 = getelementptr inbounds %Node, ptr %t58, i32 0, i32 5
  %t60 = load ptr, ptr %t59, align 8
  store ptr %t60, ptr %fc.addr.3, align 8
  br label %while.cond0
while.end0:
  ret void
}

define i32 @str-ends-with(ptr %s.arg, ptr %suffix.arg) {
entry:
  %s.addr = alloca ptr, align 8
  store ptr %s.arg, ptr %s.addr, align 8
  %suffix.addr = alloca ptr, align 8
  store ptr %suffix.arg, ptr %suffix.addr, align 8
  %slen.addr.0 = alloca i64, align 8
  %suflen.addr.3 = alloca i64, align 8
  %t1 = load ptr, ptr %s.addr, align 8
  %t2 = call i64 @strlen(ptr %t1)
  store i64 %t2, ptr %slen.addr.0, align 8
  %t4 = load ptr, ptr %suffix.addr, align 8
  %t5 = call i64 @strlen(ptr %t4)
  store i64 %t5, ptr %suflen.addr.3, align 8
  %t6 = load i64, ptr %suflen.addr.3, align 8
  %t7 = load i64, ptr %slen.addr.0, align 8
  %t8 = icmp sgt i64 %t6, %t7
  br i1 %t8, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret i32 0
cond.end0:
  %t9 = load ptr, ptr %s.addr, align 8
  %t10 = load i64, ptr %slen.addr.0, align 8
  %t11 = load i64, ptr %suflen.addr.3, align 8
  %t12 = sub nsw i64 %t10, %t11
  %t13 = getelementptr inbounds i8, ptr %t9, i64 %t12
  %t14 = load ptr, ptr %suffix.addr, align 8
  %t15 = call i32 @strcmp(ptr %t13, ptr %t14)
  %t16 = icmp eq i32 %t15, 0
  br i1 %t16, label %cond.then1.0, label %cond.end1
cond.then1.0:
  ret i32 1
cond.end1:
  ret i32 0
}

define void @emit-nuch-declare-import(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %ff.addr.0 = alloca ptr, align 8
  %or.val1 = alloca i1, align 1
  %name-node.addr.13 = alloca ptr, align 8
  %params-node.addr.16 = alloca ptr, align 8
  %fname.addr.22 = alloca ptr, align 8
  %ret-name.addr.23 = alloca ptr, align 8
  %ret.addr.37 = alloca ptr, align 8
  %nparams.addr.43 = alloca i32, align 4
  %ptypes.addr.44 = alloca ptr, align 8
  %j.addr.45 = alloca i32, align 4
  %p.addr.60 = alloca ptr, align 8
  %pn.addr.64 = alloca ptr, align 8
  %pt-name.addr.65 = alloca ptr, align 8
  %ft.addr.85 = alloca ptr, align 8
  %t1 = load ptr, ptr %form.addr, align 8
  store ptr %t1, ptr %ff.addr.0, align 8
  %t2 = load ptr, ptr %form.addr, align 8
  %t3 = call i32 @node-len(ptr %t2)
  %t4 = icmp slt i32 %t3, 2
  store i1 %t4, ptr %or.val1, align 1
  br i1 %t4, label %or.end1, label %or.rhs1
or.rhs1:
  %t5 = load ptr, ptr %form.addr, align 8
  %t6 = call i32 @node-len(ptr %t5)
  %t7 = icmp sgt i32 %t6, 3
  store i1 %t7, ptr %or.val1, align 1
  br label %or.end1
or.end1:
  %t8 = load i1, ptr %or.val1, align 1
  br i1 %t8, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t9 = load ptr, ptr %ff.addr.0, align 8
  %t10 = getelementptr inbounds %Node, ptr %t9, i32 0, i32 1
  %t11 = load i32, ptr %t10, align 4
  %t12 = getelementptr inbounds [53 x i8], ptr @.str.691, i64 0, i64 0
  call void @die-at(i32 %t11, ptr %t12)
  br label %cond.end0
cond.end0:
  %t14 = load ptr, ptr %form.addr, align 8
  %t15 = call ptr @node-at(ptr %t14, i32 1)
  store ptr %t15, ptr %name-node.addr.13, align 8
  store ptr null, ptr %params-node.addr.16, align 8
  %t17 = load ptr, ptr %form.addr, align 8
  %t18 = call i32 @node-len(ptr %t17)
  %t19 = icmp eq i32 %t18, 3
  br i1 %t19, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t20 = load ptr, ptr %form.addr, align 8
  %t21 = call ptr @node-at(ptr %t20, i32 2)
  store ptr %t21, ptr %params-node.addr.16, align 8
  br label %cond.end2
cond.end2:
  store ptr null, ptr %fname.addr.22, align 8
  store ptr null, ptr %ret-name.addr.23, align 8
  %t24 = load ptr, ptr %name-node.addr.13, align 8
  call void @extract-name-type(ptr %t24, ptr %fname.addr.22, ptr %ret-name.addr.23)
  %t25 = load ptr, ptr %ret-name.addr.23, align 8
  %t26 = icmp eq ptr %t25, null
  br i1 %t26, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t27 = load ptr, ptr %name-node.addr.13, align 8
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 1
  %t29 = load i32, ptr %t28, align 4
  %t30 = getelementptr inbounds [31 x i8], ptr @.str.692, i64 0, i64 0
  %t31 = load ptr, ptr %fname.addr.22, align 8
  %t32 = call ptr @fmt-s(ptr %t30, ptr %t31)
  call void @die-at(i32 %t29, ptr %t32)
  br label %cond.end3
cond.end3:
  %t33 = load ptr, ptr @g-globals, align 8
  %t34 = load ptr, ptr %fname.addr.22, align 8
  %t35 = call ptr @scope-lookup(ptr %t33, ptr %t34)
  %t36 = icmp ne ptr %t35, null
  br i1 %t36, label %cond.then4.0, label %cond.end4
cond.then4.0:
  ret void
cond.end4:
  %t38 = load ptr, ptr %ret-name.addr.23, align 8
  %t39 = load ptr, ptr %name-node.addr.13, align 8
  %t40 = getelementptr inbounds %Node, ptr %t39, i32 0, i32 1
  %t41 = load i32, ptr %t40, align 4
  %t42 = call ptr @parse-type-name(ptr %t38, i32 %t41)
  store ptr %t42, ptr %ret.addr.37, align 8
  store i32 0, ptr %nparams.addr.43, align 4
  store ptr null, ptr %ptypes.addr.44, align 8
  store i32 0, ptr %j.addr.45, align 4
  %t46 = load ptr, ptr %params-node.addr.16, align 8
  %t47 = icmp ne ptr %t46, null
  br i1 %t47, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t48 = load ptr, ptr %params-node.addr.16, align 8
  %t49 = call i32 @node-len(ptr %t48)
  store i32 %t49, ptr %nparams.addr.43, align 4
  br label %cond.end5
cond.end5:
  %t50 = load i32, ptr %nparams.addr.43, align 4
  %t51 = icmp sgt i32 %t50, 0
  br i1 %t51, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t52 = load i32, ptr %nparams.addr.43, align 4
  %t53 = call i64 @i64(i32 %t52)
  %t54 = call i64 @i64(i32 8)
  %t55 = mul nsw i64 %t53, %t54
  %t56 = call ptr @arena-alloc(i64 %t55)
  store ptr %t56, ptr %ptypes.addr.44, align 8
  br label %cond.end6
cond.end6:
  br label %while.cond7
while.cond7:
  %t57 = load i32, ptr %j.addr.45, align 4
  %t58 = load i32, ptr %nparams.addr.43, align 4
  %t59 = icmp slt i32 %t57, %t58
  br i1 %t59, label %while.body7, label %while.end7
while.body7:
  %t61 = load ptr, ptr %params-node.addr.16, align 8
  %t62 = load i32, ptr %j.addr.45, align 4
  %t63 = call ptr @node-at(ptr %t61, i32 %t62)
  store ptr %t63, ptr %p.addr.60, align 8
  store ptr null, ptr %pn.addr.64, align 8
  store ptr null, ptr %pt-name.addr.65, align 8
  %t66 = load ptr, ptr %p.addr.60, align 8
  call void @extract-name-type(ptr %t66, ptr %pn.addr.64, ptr %pt-name.addr.65)
  %t67 = load ptr, ptr %pt-name.addr.65, align 8
  %t68 = icmp ne ptr %t67, null
  br i1 %t68, label %cond.then8.0, label %cond.test8.1
cond.then8.0:
  %t69 = load ptr, ptr %ptypes.addr.44, align 8
  %t70 = load i32, ptr %j.addr.45, align 4
  %t71 = sext i32 %t70 to i64
  %t72 = load ptr, ptr %pt-name.addr.65, align 8
  %t73 = load ptr, ptr %p.addr.60, align 8
  %t74 = getelementptr inbounds %Node, ptr %t73, i32 0, i32 1
  %t75 = load i32, ptr %t74, align 4
  %t76 = call ptr @parse-type-name(ptr %t72, i32 %t75)
  %t77 = getelementptr inbounds ptr, ptr %t69, i64 %t71
  store ptr %t76, ptr %t77, align 8
  br label %cond.end8
cond.test8.1:
  br i1 1, label %cond.then8.1, label %cond.end8
cond.then8.1:
  %t78 = load ptr, ptr %ptypes.addr.44, align 8
  %t79 = load i32, ptr %j.addr.45, align 4
  %t80 = sext i32 %t79 to i64
  %t81 = load ptr, ptr @ty-i32, align 8
  %t82 = getelementptr inbounds ptr, ptr %t78, i64 %t80
  store ptr %t81, ptr %t82, align 8
  br label %cond.end8
cond.end8:
  %t83 = load i32, ptr %j.addr.45, align 4
  %t84 = add nsw i32 %t83, 1
  store i32 %t84, ptr %j.addr.45, align 4
  br label %while.cond7
while.end7:
  %t86 = call ptr @make-type(i32 11)
  store ptr %t86, ptr %ft.addr.85, align 8
  %t87 = load ptr, ptr %ft.addr.85, align 8
  %t88 = load ptr, ptr %ret.addr.37, align 8
  %t89 = getelementptr inbounds %Type, ptr %t87, i32 0, i32 1
  store ptr %t88, ptr %t89, align 8
  %t90 = load ptr, ptr %ft.addr.85, align 8
  %t91 = load i32, ptr %nparams.addr.43, align 4
  %t92 = getelementptr inbounds %Type, ptr %t90, i32 0, i32 3
  store i32 %t91, ptr %t92, align 4
  %t93 = load ptr, ptr %ft.addr.85, align 8
  %t94 = load ptr, ptr %ptypes.addr.44, align 8
  %t95 = getelementptr inbounds %Type, ptr %t93, i32 0, i32 2
  store ptr %t94, ptr %t95, align 8
  %t96 = load ptr, ptr %ft.addr.85, align 8
  %t97 = getelementptr inbounds %Type, ptr %t96, i32 0, i32 4
  store i32 0, ptr %t97, align 4
  %t98 = load ptr, ptr @g-globals, align 8
  %t99 = load ptr, ptr %fname.addr.22, align 8
  %t100 = load ptr, ptr %ft.addr.85, align 8
  %t101 = getelementptr inbounds [4 x i8], ptr @.str.693, i64 0, i64 0
  %t102 = load ptr, ptr %fname.addr.22, align 8
  %t103 = call ptr @fmt-s(ptr %t101, ptr %t102)
  %t104 = call ptr @scope-define(ptr %t98, ptr %t99, ptr %t100, ptr %t103, i32 0)
  %t105 = load ptr, ptr @g-out, align 8
  %t106 = getelementptr inbounds [16 x i8], ptr @.str.694, i64 0, i64 0
  %t107 = load ptr, ptr %ret.addr.37, align 8
  %t108 = call ptr @type-to-ir(ptr %t107)
  %t109 = load ptr, ptr %fname.addr.22, align 8
  %t110 = call i32 (ptr, ptr, ...) @fprintf(ptr %t105, ptr %t106, ptr %t108, ptr %t109)
  store i32 0, ptr %j.addr.45, align 4
  br label %while.cond9
while.cond9:
  %t111 = load i32, ptr %j.addr.45, align 4
  %t112 = load i32, ptr %nparams.addr.43, align 4
  %t113 = icmp slt i32 %t111, %t112
  br i1 %t113, label %while.body9, label %while.end9
while.body9:
  %t114 = load i32, ptr %j.addr.45, align 4
  %t115 = icmp ne i32 %t114, 0
  br i1 %t115, label %cond.then10.0, label %cond.end10
cond.then10.0:
  %t116 = load ptr, ptr @g-out, align 8
  %t117 = getelementptr inbounds [3 x i8], ptr @.str.695, i64 0, i64 0
  %t118 = call i32 (ptr, ptr, ...) @fprintf(ptr %t116, ptr %t117)
  br label %cond.end10
cond.end10:
  %t119 = load ptr, ptr @g-out, align 8
  %t120 = getelementptr inbounds [3 x i8], ptr @.str.696, i64 0, i64 0
  %t121 = load ptr, ptr %ptypes.addr.44, align 8
  %t122 = load i32, ptr %j.addr.45, align 4
  %t123 = sext i32 %t122 to i64
  %t124 = getelementptr inbounds ptr, ptr %t121, i64 %t123
  %t125 = load ptr, ptr %t124, align 8
  %t126 = call ptr @type-to-ir(ptr %t125)
  %t127 = call i32 (ptr, ptr, ...) @fprintf(ptr %t119, ptr %t120, ptr %t126)
  %t128 = load i32, ptr %j.addr.45, align 4
  %t129 = add nsw i32 %t128, 1
  store i32 %t129, ptr %j.addr.45, align 4
  br label %while.cond9
while.end9:
  %t130 = load ptr, ptr @g-out, align 8
  %t131 = getelementptr inbounds [3 x i8], ptr @.str.697, i64 0, i64 0
  %t132 = call i32 (ptr, ptr, ...) @fprintf(ptr %t130, ptr %t131)
  ret void
}

define void @emit-nuch-import-forms(ptr %forms.arg) {
entry:
  %forms.addr = alloca ptr, align 8
  store ptr %forms.arg, ptr %forms.addr, align 8
  %fc.addr.0 = alloca ptr, align 8
  %f.addr.4 = alloca ptr, align 8
  %and.val2 = alloca i1, align 1
  %and.val3 = alloca i1, align 1
  %and.val4 = alloca i1, align 1
  %h.addr.25 = alloca ptr, align 8
  %t1 = load ptr, ptr %forms.addr, align 8
  store ptr %t1, ptr %fc.addr.0, align 8
  br label %while.cond0
while.cond0:
  %t2 = load ptr, ptr %fc.addr.0, align 8
  %t3 = icmp ne ptr %t2, null
  br i1 %t3, label %while.body0, label %while.end0
while.body0:
  %t5 = load ptr, ptr %fc.addr.0, align 8
  %t6 = getelementptr inbounds %Node, ptr %t5, i32 0, i32 4
  %t7 = load ptr, ptr %t6, align 8
  store ptr %t7, ptr %f.addr.4, align 8
  %t8 = load ptr, ptr %f.addr.4, align 8
  %t9 = icmp ne ptr %t8, null
  store i1 %t9, ptr %and.val3, align 1
  br i1 %t9, label %and.rhs3, label %and.end3
and.rhs3:
  %t10 = load ptr, ptr %f.addr.4, align 8
  %t11 = getelementptr inbounds %Node, ptr %t10, i32 0, i32 0
  %t12 = load i32, ptr %t11, align 4
  %t13 = icmp eq i32 %t12, 3
  store i1 %t13, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t14 = load i1, ptr %and.val3, align 1
  store i1 %t14, ptr %and.val2, align 1
  br i1 %t14, label %and.rhs2, label %and.end2
and.rhs2:
  %t15 = load ptr, ptr %f.addr.4, align 8
  %t16 = call i32 @node-len(ptr %t15)
  %t17 = icmp sgt i32 %t16, 0
  store i1 %t17, ptr %and.val4, align 1
  br i1 %t17, label %and.rhs4, label %and.end4
and.rhs4:
  %t18 = load ptr, ptr %f.addr.4, align 8
  %t19 = call ptr @node-at(ptr %t18, i32 0)
  %t20 = getelementptr inbounds %Node, ptr %t19, i32 0, i32 0
  %t21 = load i32, ptr %t20, align 4
  %t22 = icmp eq i32 %t21, 2
  store i1 %t22, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t23 = load i1, ptr %and.val4, align 1
  store i1 %t23, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t24 = load i1, ptr %and.val2, align 1
  br i1 %t24, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t26 = load ptr, ptr %f.addr.4, align 8
  %t27 = call ptr @node-at(ptr %t26, i32 0)
  %t28 = getelementptr inbounds %Node, ptr %t27, i32 0, i32 3
  %t29 = load ptr, ptr %t28, align 8
  store ptr %t29, ptr %h.addr.25, align 8
  %t30 = load ptr, ptr %h.addr.25, align 8
  %t31 = getelementptr inbounds [10 x i8], ptr @.str.698, i64 0, i64 0
  %t32 = call i32 @strcmp(ptr %t30, ptr %t31)
  %t33 = icmp eq i32 %t32, 0
  br i1 %t33, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t34 = load ptr, ptr @g-type-stream, align 8
  store ptr %t34, ptr @g-out, align 8
  %t35 = load ptr, ptr %f.addr.4, align 8
  call void @emit-defstruct(ptr %t35)
  br label %cond.end5
cond.test5.1:
  %t36 = load ptr, ptr %h.addr.25, align 8
  %t37 = getelementptr inbounds [8 x i8], ptr @.str.699, i64 0, i64 0
  %t38 = call i32 @strcmp(ptr %t36, ptr %t37)
  %t39 = icmp eq i32 %t38, 0
  br i1 %t39, label %cond.then5.1, label %cond.test5.2
cond.then5.1:
  %t40 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t40, ptr @g-out, align 8
  %t41 = load ptr, ptr %f.addr.4, align 8
  call void @emit-nuch-declare-import(ptr %t41)
  br label %cond.end5
cond.test5.2:
  %t42 = load ptr, ptr %h.addr.25, align 8
  %t43 = getelementptr inbounds [9 x i8], ptr @.str.700, i64 0, i64 0
  %t44 = call i32 @strcmp(ptr %t42, ptr %t43)
  %t45 = icmp eq i32 %t44, 0
  br i1 %t45, label %cond.then5.2, label %cond.test5.3
cond.then5.2:
  %t46 = load ptr, ptr %f.addr.4, align 8
  call void @emit-defconst(ptr %t46)
  br label %cond.end5
cond.test5.3:
  %t47 = load ptr, ptr %h.addr.25, align 8
  %t48 = getelementptr inbounds [8 x i8], ptr @.str.701, i64 0, i64 0
  %t49 = call i32 @strcmp(ptr %t47, ptr %t48)
  %t50 = icmp eq i32 %t49, 0
  br i1 %t50, label %cond.then5.3, label %cond.test5.4
cond.then5.3:
  %t51 = load ptr, ptr %f.addr.4, align 8
  call void @emit-defenum(ptr %t51)
  br label %cond.end5
cond.test5.4:
  %t52 = load ptr, ptr %h.addr.25, align 8
  %t53 = getelementptr inbounds [9 x i8], ptr @.str.702, i64 0, i64 0
  %t54 = call i32 @strcmp(ptr %t52, ptr %t53)
  %t55 = icmp eq i32 %t54, 0
  br i1 %t55, label %cond.then5.4, label %cond.test5.5
cond.then5.4:
  %t56 = load ptr, ptr %f.addr.4, align 8
  call void @emit-defmacro(ptr %t56)
  br label %cond.end5
cond.test5.5:
  %t57 = load ptr, ptr %h.addr.25, align 8
  %t58 = getelementptr inbounds [11 x i8], ptr @.str.703, i64 0, i64 0
  %t59 = call i32 @strcmp(ptr %t57, ptr %t58)
  %t60 = icmp eq i32 %t59, 0
  br i1 %t60, label %cond.then5.5, label %cond.test5.6
cond.then5.5:
  %t61 = load ptr, ptr %f.addr.4, align 8
  call void @emit-def-rmacro(ptr %t61)
  br label %cond.end5
cond.test5.6:
  br i1 1, label %cond.then5.6, label %cond.end5
cond.then5.6:
  br label %cond.end5
cond.end5:
  br label %cond.end1
cond.end1:
  %t62 = load ptr, ptr %fc.addr.0, align 8
  %t63 = getelementptr inbounds %Node, ptr %t62, i32 0, i32 5
  %t64 = load ptr, ptr %t63, align 8
  store ptr %t64, ptr %fc.addr.0, align 8
  br label %while.cond0
while.end0:
  ret void
}

define void @register-rmacro(ptr %prefix.arg, ptr %wrap-sym.arg) {
entry:
  %prefix.addr = alloca ptr, align 8
  store ptr %prefix.arg, ptr %prefix.addr, align 8
  %wrap-sym.addr = alloca ptr, align 8
  store ptr %wrap-sym.arg, ptr %wrap-sym.addr, align 8
  %rm.addr.0 = alloca ptr, align 8
  %t1 = load ptr, ptr @g-rmacros, align 8
  %t2 = load i32, ptr @g-num-rmacros, align 4
  %t3 = sext i32 %t2 to i64
  %t4 = getelementptr inbounds %RMacro, ptr %t1, i64 %t3
  store ptr %t4, ptr %rm.addr.0, align 8
  %t5 = load ptr, ptr %rm.addr.0, align 8
  %t6 = load ptr, ptr %prefix.addr, align 8
  %t7 = getelementptr inbounds %RMacro, ptr %t5, i32 0, i32 0
  store ptr %t6, ptr %t7, align 8
  %t8 = load ptr, ptr %rm.addr.0, align 8
  %t9 = load ptr, ptr %prefix.addr, align 8
  %t10 = call i64 @strlen(ptr %t9)
  %t11 = trunc i64 %t10 to i32
  %t12 = getelementptr inbounds %RMacro, ptr %t8, i32 0, i32 1
  store i32 %t11, ptr %t12, align 4
  %t13 = load ptr, ptr %rm.addr.0, align 8
  %t14 = load ptr, ptr %wrap-sym.addr, align 8
  %t15 = getelementptr inbounds %RMacro, ptr %t13, i32 0, i32 2
  store ptr %t14, ptr %t15, align 8
  %t16 = load i32, ptr @g-num-rmacros, align 4
  %t17 = add nsw i32 %t16, 1
  store i32 %t17, ptr @g-num-rmacros, align 4
  ret void
}

define void @init-rmacros() {
entry:
  %t0 = sext i32 64 to i64
  %t1 = getelementptr %RMacro, ptr null, i32 1
  %t2 = ptrtoint ptr %t1 to i64
  %t3 = mul nsw i64 %t0, %t2
  %t4 = call ptr @arena-alloc(i64 %t3)
  store ptr %t4, ptr @g-rmacros, align 8
  %t5 = getelementptr inbounds [3 x i8], ptr @.str.704, i64 0, i64 0
  %t6 = getelementptr inbounds [15 x i8], ptr @.str.705, i64 0, i64 0
  call void @register-rmacro(ptr %t5, ptr %t6)
  %t7 = getelementptr inbounds [2 x i8], ptr @.str.706, i64 0, i64 0
  %t8 = getelementptr inbounds [8 x i8], ptr @.str.707, i64 0, i64 0
  call void @register-rmacro(ptr %t7, ptr %t8)
  %t9 = getelementptr inbounds [2 x i8], ptr @.str.708, i64 0, i64 0
  %t10 = getelementptr inbounds [6 x i8], ptr @.str.709, i64 0, i64 0
  call void @register-rmacro(ptr %t9, ptr %t10)
  %t11 = getelementptr inbounds [2 x i8], ptr @.str.710, i64 0, i64 0
  %t12 = getelementptr inbounds [11 x i8], ptr @.str.711, i64 0, i64 0
  call void @register-rmacro(ptr %t11, ptr %t12)
  %t13 = getelementptr inbounds [2 x i8], ptr @.str.712, i64 0, i64 0
  %t14 = getelementptr inbounds [6 x i8], ptr @.str.713, i64 0, i64 0
  call void @register-rmacro(ptr %t13, ptr %t14)
  ret void
}

define void @compiler-init() {
entry:
  call void @arena-init()
  call void @types-init()
  call void @init-binops()
  call void @init-rmacros()
  %t0 = sext i32 64 to i64
  %t1 = getelementptr %StructDef, ptr null, i32 1
  %t2 = ptrtoint ptr %t1 to i64
  %t3 = mul nsw i64 %t0, %t2
  %t4 = call ptr @arena-alloc(i64 %t3)
  store ptr %t4, ptr @g-structs, align 8
  %t5 = sext i32 256 to i64
  %t6 = getelementptr %MacroDef, ptr null, i32 1
  %t7 = ptrtoint ptr %t6 to i64
  %t8 = mul nsw i64 %t5, %t7
  %t9 = call ptr @arena-alloc(i64 %t8)
  store ptr %t9, ptr @g-macros, align 8
  %t10 = call ptr @scope-new(ptr null)
  store ptr %t10, ptr @g-globals, align 8
  ret void
}

define void @emit-qq-helpers(ptr %decl.arg, ptr %def.arg) {
entry:
  %decl.addr = alloca ptr, align 8
  store ptr %decl.arg, ptr %decl.addr, align 8
  %def.addr = alloca ptr, align 8
  store ptr %def.arg, ptr %def.addr, align 8
  %t0 = load ptr, ptr %decl.addr, align 8
  %t1 = getelementptr inbounds [26 x i8], ptr @.str.714, i64 0, i64 0
  %t2 = call i32 (ptr, ptr, ...) @fprintf(ptr %t0, ptr %t1)
  %t3 = load ptr, ptr %def.addr, align 8
  %t4 = getelementptr inbounds [40 x i8], ptr @.str.715, i64 0, i64 0
  %t5 = call i32 (ptr, ptr, ...) @fprintf(ptr %t3, ptr %t4)
  %t6 = load ptr, ptr %def.addr, align 8
  %t7 = getelementptr inbounds [34 x i8], ptr @.str.716, i64 0, i64 0
  %t8 = call i32 (ptr, ptr, ...) @fprintf(ptr %t6, ptr %t7)
  %t9 = load ptr, ptr %def.addr, align 8
  %t10 = getelementptr inbounds [89 x i8], ptr @.str.717, i64 0, i64 0
  %t11 = call i32 (ptr, ptr, ...) @fprintf(ptr %t9, ptr %t10)
  %t12 = load ptr, ptr %def.addr, align 8
  %t13 = getelementptr inbounds [34 x i8], ptr @.str.718, i64 0, i64 0
  %t14 = call i32 (ptr, ptr, ...) @fprintf(ptr %t12, ptr %t13)
  %t15 = load ptr, ptr %def.addr, align 8
  %t16 = getelementptr inbounds [89 x i8], ptr @.str.719, i64 0, i64 0
  %t17 = call i32 (ptr, ptr, ...) @fprintf(ptr %t15, ptr %t16)
  %t18 = load ptr, ptr %def.addr, align 8
  %t19 = getelementptr inbounds [34 x i8], ptr @.str.720, i64 0, i64 0
  %t20 = call i32 (ptr, ptr, ...) @fprintf(ptr %t18, ptr %t19)
  %t21 = load ptr, ptr %def.addr, align 8
  %t22 = getelementptr inbounds [89 x i8], ptr @.str.721, i64 0, i64 0
  %t23 = call i32 (ptr, ptr, ...) @fprintf(ptr %t21, ptr %t22)
  %t24 = load ptr, ptr %def.addr, align 8
  %t25 = getelementptr inbounds [34 x i8], ptr @.str.722, i64 0, i64 0
  %t26 = call i32 (ptr, ptr, ...) @fprintf(ptr %t24, ptr %t25)
  %t27 = load ptr, ptr %def.addr, align 8
  %t28 = getelementptr inbounds [89 x i8], ptr @.str.723, i64 0, i64 0
  %t29 = call i32 (ptr, ptr, ...) @fprintf(ptr %t27, ptr %t28)
  %t30 = load ptr, ptr %def.addr, align 8
  %t31 = getelementptr inbounds [37 x i8], ptr @.str.724, i64 0, i64 0
  %t32 = call i32 (ptr, ptr, ...) @fprintf(ptr %t30, ptr %t31)
  %t33 = load ptr, ptr %def.addr, align 8
  %t34 = getelementptr inbounds [89 x i8], ptr @.str.725, i64 0, i64 0
  %t35 = call i32 (ptr, ptr, ...) @fprintf(ptr %t33, ptr %t34)
  %t36 = load ptr, ptr %def.addr, align 8
  %t37 = getelementptr inbounds [36 x i8], ptr @.str.726, i64 0, i64 0
  %t38 = call i32 (ptr, ptr, ...) @fprintf(ptr %t36, ptr %t37)
  %t39 = load ptr, ptr %def.addr, align 8
  %t40 = getelementptr inbounds [89 x i8], ptr @.str.727, i64 0, i64 0
  %t41 = call i32 (ptr, ptr, ...) @fprintf(ptr %t39, ptr %t40)
  %t42 = load ptr, ptr %def.addr, align 8
  %t43 = getelementptr inbounds [36 x i8], ptr @.str.728, i64 0, i64 0
  %t44 = call i32 (ptr, ptr, ...) @fprintf(ptr %t42, ptr %t43)
  %t45 = load ptr, ptr %def.addr, align 8
  %t46 = getelementptr inbounds [15 x i8], ptr @.str.729, i64 0, i64 0
  %t47 = call i32 (ptr, ptr, ...) @fprintf(ptr %t45, ptr %t46)
  %t48 = load ptr, ptr %def.addr, align 8
  %t49 = getelementptr inbounds [4 x i8], ptr @.str.730, i64 0, i64 0
  %t50 = call i32 (ptr, ptr, ...) @fprintf(ptr %t48, ptr %t49)
  %t51 = load ptr, ptr %def.addr, align 8
  %t52 = getelementptr inbounds [42 x i8], ptr @.str.731, i64 0, i64 0
  %t53 = call i32 (ptr, ptr, ...) @fprintf(ptr %t51, ptr %t52)
  %t54 = load ptr, ptr %def.addr, align 8
  %t55 = getelementptr inbounds [8 x i8], ptr @.str.732, i64 0, i64 0
  %t56 = call i32 (ptr, ptr, ...) @fprintf(ptr %t54, ptr %t55)
  %t57 = load ptr, ptr %def.addr, align 8
  %t58 = getelementptr inbounds [31 x i8], ptr @.str.733, i64 0, i64 0
  %t59 = call i32 (ptr, ptr, ...) @fprintf(ptr %t57, ptr %t58)
  %t60 = load ptr, ptr %def.addr, align 8
  %t61 = getelementptr inbounds [39 x i8], ptr @.str.734, i64 0, i64 0
  %t62 = call i32 (ptr, ptr, ...) @fprintf(ptr %t60, ptr %t61)
  %t63 = load ptr, ptr %def.addr, align 8
  %t64 = getelementptr inbounds [6 x i8], ptr @.str.735, i64 0, i64 0
  %t65 = call i32 (ptr, ptr, ...) @fprintf(ptr %t63, ptr %t64)
  %t66 = load ptr, ptr %def.addr, align 8
  %t67 = getelementptr inbounds [15 x i8], ptr @.str.736, i64 0, i64 0
  %t68 = call i32 (ptr, ptr, ...) @fprintf(ptr %t66, ptr %t67)
  %t69 = load ptr, ptr %def.addr, align 8
  %t70 = getelementptr inbounds [6 x i8], ptr @.str.737, i64 0, i64 0
  %t71 = call i32 (ptr, ptr, ...) @fprintf(ptr %t69, ptr %t70)
  %t72 = load ptr, ptr %def.addr, align 8
  %t73 = getelementptr inbounds [89 x i8], ptr @.str.738, i64 0, i64 0
  %t74 = call i32 (ptr, ptr, ...) @fprintf(ptr %t72, ptr %t73)
  %t75 = load ptr, ptr %def.addr, align 8
  %t76 = getelementptr inbounds [39 x i8], ptr @.str.739, i64 0, i64 0
  %t77 = call i32 (ptr, ptr, ...) @fprintf(ptr %t75, ptr %t76)
  %t78 = load ptr, ptr %def.addr, align 8
  %t79 = getelementptr inbounds [89 x i8], ptr @.str.740, i64 0, i64 0
  %t80 = call i32 (ptr, ptr, ...) @fprintf(ptr %t78, ptr %t79)
  %t81 = load ptr, ptr %def.addr, align 8
  %t82 = getelementptr inbounds [39 x i8], ptr @.str.741, i64 0, i64 0
  %t83 = call i32 (ptr, ptr, ...) @fprintf(ptr %t81, ptr %t82)
  %t84 = load ptr, ptr %def.addr, align 8
  %t85 = getelementptr inbounds [51 x i8], ptr @.str.742, i64 0, i64 0
  %t86 = call i32 (ptr, ptr, ...) @fprintf(ptr %t84, ptr %t85)
  %t87 = load ptr, ptr %def.addr, align 8
  %t88 = getelementptr inbounds [49 x i8], ptr @.str.743, i64 0, i64 0
  %t89 = call i32 (ptr, ptr, ...) @fprintf(ptr %t87, ptr %t88)
  %t90 = load ptr, ptr %def.addr, align 8
  %t91 = getelementptr inbounds [15 x i8], ptr @.str.744, i64 0, i64 0
  %t92 = call i32 (ptr, ptr, ...) @fprintf(ptr %t90, ptr %t91)
  %t93 = load ptr, ptr %def.addr, align 8
  %t94 = getelementptr inbounds [4 x i8], ptr @.str.745, i64 0, i64 0
  %t95 = call i32 (ptr, ptr, ...) @fprintf(ptr %t93, ptr %t94)
  ret void
}

define void @open-module-streams() {
entry:
  %t0 = call ptr @open_memstream(ptr @g-type-bufp, ptr @g-type-sizep)
  store ptr %t0, ptr @g-type-stream, align 8
  %t1 = call ptr @open_memstream(ptr @g-decl-bufp, ptr @g-decl-sizep)
  store ptr %t1, ptr @g-decl-stream, align 8
  %t2 = call ptr @open_memstream(ptr @g-def-bufp, ptr @g-def-sizep)
  store ptr %t2, ptr @g-def-stream, align 8
  %t3 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t3, ptr @g-decl-out, align 8
  ret void
}

define void @flush-module-ir(ptr %source-file.arg) {
entry:
  %source-file.addr = alloca ptr, align 8
  store ptr %source-file.arg, ptr %source-file.addr, align 8
  %and.val2 = alloca i1, align 1
  %and.val4 = alloca i1, align 1
  %and.val6 = alloca i1, align 1
  %t0 = load i32, ptr @g-qq-used, align 4
  %t1 = icmp ne i32 %t0, 0
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t2 = load ptr, ptr @g-decl-stream, align 8
  %t3 = load ptr, ptr @g-def-stream, align 8
  call void @emit-qq-helpers(ptr %t2, ptr %t3)
  br label %cond.end0
cond.end0:
  %t4 = load ptr, ptr @g-type-stream, align 8
  %t5 = call i32 @fclose(ptr %t4)
  %t6 = load ptr, ptr @g-decl-stream, align 8
  %t7 = call i32 @fclose(ptr %t6)
  %t8 = load ptr, ptr @g-def-stream, align 8
  %t9 = call i32 @fclose(ptr %t8)
  %t10 = getelementptr inbounds [19 x i8], ptr @.str.746, i64 0, i64 0
  %t11 = load ptr, ptr %source-file.addr, align 8
  %t12 = call i32 (ptr, ...) @printf(ptr %t10, ptr %t11)
  %t13 = getelementptr inbounds [24 x i8], ptr @.str.747, i64 0, i64 0
  %t14 = load ptr, ptr %source-file.addr, align 8
  %t15 = call i32 (ptr, ...) @printf(ptr %t13, ptr %t14)
  %t16 = getelementptr inbounds [40 x i8], ptr @.str.748, i64 0, i64 0
  %t17 = call i32 (ptr, ...) @printf(ptr %t16)
  %t18 = load ptr, ptr @g-type-bufp, align 8
  %t19 = icmp ne ptr %t18, null
  store i1 %t19, ptr %and.val2, align 1
  br i1 %t19, label %and.rhs2, label %and.end2
and.rhs2:
  %t20 = load ptr, ptr @g-type-bufp, align 8
  %t21 = sext i32 0 to i64
  %t22 = call i32 @char-at(ptr %t20, i64 %t21)
  %t23 = icmp ne i32 %t22, 0
  store i1 %t23, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t24 = load i1, ptr %and.val2, align 1
  br i1 %t24, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t25 = load ptr, ptr @g-type-bufp, align 8
  %t26 = load ptr, ptr @stdout, align 8
  %t27 = call i32 @fputs(ptr %t25, ptr %t26)
  br label %cond.end1
cond.end1:
  %t28 = load ptr, ptr @stdout, align 8
  call void @emit-string-table(ptr %t28)
  %t29 = load ptr, ptr @g-decl-bufp, align 8
  %t30 = icmp ne ptr %t29, null
  store i1 %t30, ptr %and.val4, align 1
  br i1 %t30, label %and.rhs4, label %and.end4
and.rhs4:
  %t31 = load ptr, ptr @g-decl-bufp, align 8
  %t32 = sext i32 0 to i64
  %t33 = call i32 @char-at(ptr %t31, i64 %t32)
  %t34 = icmp ne i32 %t33, 0
  store i1 %t34, ptr %and.val4, align 1
  br label %and.end4
and.end4:
  %t35 = load i1, ptr %and.val4, align 1
  br i1 %t35, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t36 = load ptr, ptr @g-decl-bufp, align 8
  %t37 = load ptr, ptr @stdout, align 8
  %t38 = call i32 @fputs(ptr %t36, ptr %t37)
  br label %cond.end3
cond.end3:
  %t39 = load ptr, ptr @g-def-bufp, align 8
  %t40 = icmp ne ptr %t39, null
  store i1 %t40, ptr %and.val6, align 1
  br i1 %t40, label %and.rhs6, label %and.end6
and.rhs6:
  %t41 = load ptr, ptr @g-def-bufp, align 8
  %t42 = sext i32 0 to i64
  %t43 = call i32 @char-at(ptr %t41, i64 %t42)
  %t44 = icmp ne i32 %t43, 0
  store i1 %t44, ptr %and.val6, align 1
  br label %and.end6
and.end6:
  %t45 = load i1, ptr %and.val6, align 1
  br i1 %t45, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t46 = load ptr, ptr @g-def-bufp, align 8
  %t47 = load ptr, ptr @stdout, align 8
  %t48 = call i32 @fputs(ptr %t46, ptr %t47)
  br label %cond.end5
cond.end5:
  %t49 = load ptr, ptr @g-type-bufp, align 8
  call void @free(ptr %t49)
  %t50 = load ptr, ptr @g-decl-bufp, align 8
  call void @free(ptr %t50)
  %t51 = load ptr, ptr @g-def-bufp, align 8
  call void @free(ptr %t51)
  ret void
}

define ptr @repl-read-input() {
entry:
  %buf.addr.0 = alloca ptr, align 8
  %buf-len.addr.3 = alloca i64, align 8
  %buf-cap.addr.5 = alloca i64, align 8
  %depth.addr.7 = alloca i32, align 4
  %got-input.addr.8 = alloca i32, align 4
  %in-string.addr.9 = alloca i32, align 4
  %in-comment.addr.10 = alloca i32, align 4
  %first-line.addr.11 = alloca i32, align 4
  %done.addr.19 = alloca i32, align 4
  %line-buf.addr.32 = alloca ptr, align 8
  %line-len.addr.48 = alloca i64, align 8
  %new-cap.addr.58 = alloca i64, align 8
  %li.addr.92 = alloca i64, align 8
  %c.addr.97 = alloca i32, align 4
  %and.val15 = alloca i1, align 1
  %t1 = sext i32 4096 to i64
  %t2 = call ptr @malloc(i64 %t1)
  store ptr %t2, ptr %buf.addr.0, align 8
  %t4 = sext i32 0 to i64
  store i64 %t4, ptr %buf-len.addr.3, align 8
  %t6 = sext i32 4096 to i64
  store i64 %t6, ptr %buf-cap.addr.5, align 8
  store i32 0, ptr %depth.addr.7, align 4
  store i32 0, ptr %got-input.addr.8, align 4
  store i32 0, ptr %in-string.addr.9, align 4
  store i32 0, ptr %in-comment.addr.10, align 4
  store i32 1, ptr %first-line.addr.11, align 4
  %t12 = load ptr, ptr %buf.addr.0, align 8
  %t13 = icmp eq ptr %t12, null
  br i1 %t13, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t14 = getelementptr inbounds [7 x i8], ptr @.str.749, i64 0, i64 0
  call void @perror(ptr %t14)
  call void @exit(i32 1)
  br label %cond.end0
cond.end0:
  %t15 = load ptr, ptr %buf.addr.0, align 8
  %t16 = sext i32 0 to i64
  %t17 = trunc i32 0 to i8
  %t18 = getelementptr inbounds i8, ptr %t15, i64 %t16
  store i8 %t17, ptr %t18, align 1
  store i32 0, ptr %done.addr.19, align 4
  br label %while.cond1
while.cond1:
  %t20 = load i32, ptr %done.addr.19, align 4
  %t21 = icmp eq i32 %t20, 0
  br i1 %t21, label %while.body1, label %while.end1
while.body1:
  %t22 = load i32, ptr %first-line.addr.11, align 4
  %t23 = icmp ne i32 %t22, 0
  br i1 %t23, label %cond.then2.0, label %cond.test2.1
cond.then2.0:
  %t24 = load ptr, ptr @stderr, align 8
  %t25 = getelementptr inbounds [6 x i8], ptr @.str.750, i64 0, i64 0
  %t26 = call i32 (ptr, ptr, ...) @fprintf(ptr %t24, ptr %t25)
  br label %cond.end2
cond.test2.1:
  br i1 1, label %cond.then2.1, label %cond.end2
cond.then2.1:
  %t27 = load ptr, ptr @stderr, align 8
  %t28 = getelementptr inbounds [6 x i8], ptr @.str.751, i64 0, i64 0
  %t29 = call i32 (ptr, ptr, ...) @fprintf(ptr %t27, ptr %t28)
  br label %cond.end2
cond.end2:
  %t30 = load ptr, ptr @stderr, align 8
  %t31 = call i32 @fflush(ptr %t30)
  %t33 = sext i32 4096 to i64
  %t34 = call ptr @malloc(i64 %t33)
  store ptr %t34, ptr %line-buf.addr.32, align 8
  %t35 = load ptr, ptr %line-buf.addr.32, align 8
  %t36 = icmp eq ptr %t35, null
  br i1 %t36, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t37 = getelementptr inbounds [7 x i8], ptr @.str.752, i64 0, i64 0
  call void @perror(ptr %t37)
  call void @exit(i32 1)
  br label %cond.end3
cond.end3:
  %t38 = load ptr, ptr %line-buf.addr.32, align 8
  %t39 = load ptr, ptr @stdin, align 8
  %t40 = call ptr @fgets(ptr %t38, i32 4096, ptr %t39)
  %t41 = icmp eq ptr %t40, null
  br i1 %t41, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t42 = load ptr, ptr %line-buf.addr.32, align 8
  call void @free(ptr %t42)
  %t43 = load i32, ptr %got-input.addr.8, align 4
  %t44 = icmp eq i32 %t43, 0
  br i1 %t44, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t45 = load ptr, ptr %buf.addr.0, align 8
  call void @free(ptr %t45)
  ret ptr null
cond.test5.1:
  br i1 1, label %cond.then5.1, label %cond.end5
cond.then5.1:
  store i32 1, ptr %done.addr.19, align 4
  br label %cond.end5
cond.end5:
  br label %cond.end4
cond.end4:
  %t46 = load i32, ptr %done.addr.19, align 4
  %t47 = icmp eq i32 %t46, 0
  br i1 %t47, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t49 = load ptr, ptr %line-buf.addr.32, align 8
  %t50 = call i64 @strlen(ptr %t49)
  store i64 %t50, ptr %line-len.addr.48, align 8
  %t51 = load i64, ptr %buf-len.addr.3, align 8
  %t52 = load i64, ptr %line-len.addr.48, align 8
  %t53 = add nsw i64 %t51, %t52
  %t54 = load i64, ptr %buf-cap.addr.5, align 8
  %t55 = sext i32 1 to i64
  %t56 = sub nsw i64 %t54, %t55
  %t57 = icmp sgt i64 %t53, %t56
  br i1 %t57, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t59 = load i64, ptr %buf-cap.addr.5, align 8
  %t60 = sext i32 2 to i64
  %t61 = mul nsw i64 %t59, %t60
  store i64 %t61, ptr %new-cap.addr.58, align 8
  br label %while.cond8
while.cond8:
  %t62 = load i64, ptr %buf-len.addr.3, align 8
  %t63 = load i64, ptr %line-len.addr.48, align 8
  %t64 = add nsw i64 %t62, %t63
  %t65 = load i64, ptr %new-cap.addr.58, align 8
  %t66 = sext i32 1 to i64
  %t67 = sub nsw i64 %t65, %t66
  %t68 = icmp sgt i64 %t64, %t67
  br i1 %t68, label %while.body8, label %while.end8
while.body8:
  %t69 = load i64, ptr %new-cap.addr.58, align 8
  %t70 = sext i32 2 to i64
  %t71 = mul nsw i64 %t69, %t70
  store i64 %t71, ptr %new-cap.addr.58, align 8
  br label %while.cond8
while.end8:
  %t72 = load ptr, ptr %buf.addr.0, align 8
  %t73 = load i64, ptr %new-cap.addr.58, align 8
  %t74 = call ptr @realloc(ptr %t72, i64 %t73)
  store ptr %t74, ptr %buf.addr.0, align 8
  %t75 = load ptr, ptr %buf.addr.0, align 8
  %t76 = icmp eq ptr %t75, null
  br i1 %t76, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t77 = getelementptr inbounds [8 x i8], ptr @.str.753, i64 0, i64 0
  call void @perror(ptr %t77)
  call void @exit(i32 1)
  br label %cond.end9
cond.end9:
  %t78 = load i64, ptr %new-cap.addr.58, align 8
  store i64 %t78, ptr %buf-cap.addr.5, align 8
  br label %cond.end7
cond.end7:
  %t79 = load ptr, ptr %buf.addr.0, align 8
  %t80 = load i64, ptr %buf-len.addr.3, align 8
  %t81 = getelementptr inbounds i8, ptr %t79, i64 %t80
  %t82 = load ptr, ptr %line-buf.addr.32, align 8
  %t83 = load i64, ptr %line-len.addr.48, align 8
  %t84 = call ptr @memcpy(ptr %t81, ptr %t82, i64 %t83)
  %t85 = load i64, ptr %buf-len.addr.3, align 8
  %t86 = load i64, ptr %line-len.addr.48, align 8
  %t87 = add nsw i64 %t85, %t86
  store i64 %t87, ptr %buf-len.addr.3, align 8
  %t88 = load ptr, ptr %buf.addr.0, align 8
  %t89 = load i64, ptr %buf-len.addr.3, align 8
  %t90 = trunc i32 0 to i8
  %t91 = getelementptr inbounds i8, ptr %t88, i64 %t89
  store i8 %t90, ptr %t91, align 1
  store i32 1, ptr %got-input.addr.8, align 4
  store i32 0, ptr %first-line.addr.11, align 4
  %t93 = sext i32 0 to i64
  store i64 %t93, ptr %li.addr.92, align 8
  br label %while.cond10
while.cond10:
  %t94 = load i64, ptr %li.addr.92, align 8
  %t95 = load i64, ptr %line-len.addr.48, align 8
  %t96 = icmp slt i64 %t94, %t95
  br i1 %t96, label %while.body10, label %while.end10
while.body10:
  %t98 = load ptr, ptr %line-buf.addr.32, align 8
  %t99 = load i64, ptr %li.addr.92, align 8
  %t100 = getelementptr inbounds i8, ptr %t98, i64 %t99
  %t101 = load i8, ptr %t100, align 1
  %t102 = sext i8 %t101 to i32
  %t103 = and i32 %t102, 255
  store i32 %t103, ptr %c.addr.97, align 4
  %t104 = load i32, ptr %in-comment.addr.10, align 4
  %t105 = icmp ne i32 %t104, 0
  br i1 %t105, label %cond.then11.0, label %cond.test11.1
cond.then11.0:
  %t106 = load i32, ptr %c.addr.97, align 4
  %t107 = icmp eq i32 %t106, 10
  br i1 %t107, label %cond.then12.0, label %cond.end12
cond.then12.0:
  store i32 0, ptr %in-comment.addr.10, align 4
  br label %cond.end12
cond.end12:
  br label %cond.end11
cond.test11.1:
  %t108 = load i32, ptr %in-string.addr.9, align 4
  %t109 = icmp ne i32 %t108, 0
  br i1 %t109, label %cond.then11.1, label %cond.test11.2
cond.then11.1:
  %t110 = load i32, ptr %c.addr.97, align 4
  %t111 = icmp eq i32 %t110, 92
  br i1 %t111, label %cond.then13.0, label %cond.test13.1
cond.then13.0:
  %t112 = load i64, ptr %li.addr.92, align 8
  %t113 = sext i32 1 to i64
  %t114 = add nsw i64 %t112, %t113
  store i64 %t114, ptr %li.addr.92, align 8
  br label %cond.end13
cond.test13.1:
  %t115 = load i32, ptr %c.addr.97, align 4
  %t116 = icmp eq i32 %t115, 34
  br i1 %t116, label %cond.then13.1, label %cond.test13.2
cond.then13.1:
  store i32 0, ptr %in-string.addr.9, align 4
  br label %cond.end13
cond.test13.2:
  br i1 1, label %cond.then13.2, label %cond.end13
cond.then13.2:
  br label %cond.end13
cond.end13:
  br label %cond.end11
cond.test11.2:
  %t117 = load i32, ptr %c.addr.97, align 4
  %t118 = icmp eq i32 %t117, 59
  br i1 %t118, label %cond.then11.2, label %cond.test11.3
cond.then11.2:
  store i32 1, ptr %in-comment.addr.10, align 4
  br label %cond.end11
cond.test11.3:
  %t119 = load i32, ptr %c.addr.97, align 4
  %t120 = icmp eq i32 %t119, 34
  br i1 %t120, label %cond.then11.3, label %cond.test11.4
cond.then11.3:
  store i32 1, ptr %in-string.addr.9, align 4
  br label %cond.end11
cond.test11.4:
  %t121 = load i32, ptr %c.addr.97, align 4
  %t122 = icmp eq i32 %t121, 40
  br i1 %t122, label %cond.then11.4, label %cond.test11.5
cond.then11.4:
  %t123 = load i32, ptr %depth.addr.7, align 4
  %t124 = add nsw i32 %t123, 1
  store i32 %t124, ptr %depth.addr.7, align 4
  br label %cond.end11
cond.test11.5:
  %t125 = load i32, ptr %c.addr.97, align 4
  %t126 = icmp eq i32 %t125, 41
  br i1 %t126, label %cond.then11.5, label %cond.test11.6
cond.then11.5:
  %t127 = load i32, ptr %depth.addr.7, align 4
  %t128 = sub nsw i32 %t127, 1
  store i32 %t128, ptr %depth.addr.7, align 4
  br label %cond.end11
cond.test11.6:
  br i1 1, label %cond.then11.6, label %cond.end11
cond.then11.6:
  br label %cond.end11
cond.end11:
  %t129 = load i64, ptr %li.addr.92, align 8
  %t130 = sext i32 1 to i64
  %t131 = add nsw i64 %t129, %t130
  store i64 %t131, ptr %li.addr.92, align 8
  br label %while.cond10
while.end10:
  %t132 = load ptr, ptr %line-buf.addr.32, align 8
  call void @free(ptr %t132)
  %t133 = load i32, ptr %depth.addr.7, align 4
  %t134 = icmp sle i32 %t133, 0
  store i1 %t134, ptr %and.val15, align 1
  br i1 %t134, label %and.rhs15, label %and.end15
and.rhs15:
  %t135 = load i32, ptr %got-input.addr.8, align 4
  %t136 = icmp ne i32 %t135, 0
  store i1 %t136, ptr %and.val15, align 1
  br label %and.end15
and.end15:
  %t137 = load i1, ptr %and.val15, align 1
  br i1 %t137, label %cond.then14.0, label %cond.end14
cond.then14.0:
  store i32 1, ptr %done.addr.19, align 4
  br label %cond.end14
cond.end14:
  br label %cond.end6
cond.end6:
  br label %while.cond1
while.end1:
  %t138 = load ptr, ptr %buf.addr.0, align 8
  ret ptr %t138
}

define void @repl-eval-form(ptr %form.arg) {
entry:
  %form.addr = alloca ptr, align 8
  store ptr %form.arg, ptr %form.addr, align 8
  %f.addr.0 = alloca ptr, align 8
  %h.addr.4 = alloca ptr, align 8
  %is-expr.addr.5 = alloca i32, align 4
  %and.val2 = alloca i1, align 1
  %and.val3 = alloca i1, align 1
  %and.val5 = alloca i1, align 1
  %and.val6 = alloca i1, align 1
  %and.val7 = alloca i1, align 1
  %var-node.addr.52 = alloca ptr, align 8
  %vname.addr.57 = alloca ptr, align 8
  %vtype-name.addr.58 = alloca ptr, align 8
  %vty.addr.62 = alloca ptr, align 8
  %and.val10 = alloca i1, align 1
  %and.val12 = alloca i1, align 1
  %and.val13 = alloca i1, align 1
  %and.val15 = alloca i1, align 1
  %and.val16 = alloca i1, align 1
  %and.val18 = alloca i1, align 1
  %and.val19 = alloca i1, align 1
  %redef.addr.172 = alloca i32, align 4
  %name-node.addr.173 = alloca ptr, align 8
  %fname.addr.178 = alloca ptr, align 8
  %ret-name.addr.179 = alloca ptr, align 8
  %one-form.addr.191 = alloca ptr, align 8
  %name-node2.addr.207 = alloca ptr, align 8
  %fname2.addr.212 = alloca ptr, align 8
  %ret-name2.addr.213 = alloca ptr, align 8
  %sym.addr.215 = alloca ptr, align 8
  %ft.addr.221 = alloca ptr, align 8
  %pi.addr.238 = alloca i32, align 4
  %sep.addr.266 = alloca ptr, align 8
  %and.val31 = alloca i1, align 1
  %and.val32 = alloca i1, align 1
  %and.val33 = alloca i1, align 1
  %and.val34 = alloca i1, align 1
  %pre-len.addr.320 = alloca i32, align 4
  %and.val36 = alloca i1, align 1
  %si.addr.340 = alloca i32, align 4
  %sym.addr.347 = alloca ptr, align 8
  %ft.addr.354 = alloca ptr, align 8
  %is-dup.addr.362 = alloca i32, align 4
  %dj.addr.363 = alloca i32, align 4
  %nxt.addr.371 = alloca ptr, align 8
  %pi.addr.400 = alloca i32, align 4
  %sep.addr.428 = alloca ptr, align 8
  %eval-sym.addr.444 = alloca ptr, align 8
  %fn-scope.addr.452 = alloca ptr, align 8
  %result.addr.455 = alloca ptr, align 8
  %result-kind.addr.459 = alloca i32, align 4
  %or.val48 = alloca i1, align 1
  %or.val49 = alloca i1, align 1
  %or.val50 = alloca i1, align 1
  %ret-val.addr.483 = alloca ptr, align 8
  %ext-tmp.addr.489 = alloca ptr, align 8
  %ret-ir.addr.546 = alloca ptr, align 8
  %or.val54 = alloca i1, align 1
  %or.val55 = alloca i1, align 1
  %or.val56 = alloca i1, align 1
  %and.val60 = alloca i1, align 1
  %and.val62 = alloca i1, align 1
  %addr.addr.606 = alloca i64, align 8
  %err.addr.608 = alloca ptr, align 8
  %or.val67 = alloca i1, align 1
  %or.val68 = alloca i1, align 1
  %or.val69 = alloca i1, align 1
  %fn.addr.633 = alloca ptr, align 8
  %rv.addr.636 = alloca i32, align 4
  %fn.addr.645 = alloca ptr, align 8
  %rv.addr.648 = alloca i64, align 8
  %fn.addr.657 = alloca ptr, align 8
  %rv.addr.660 = alloca ptr, align 8
  %t1 = load ptr, ptr %form.addr, align 8
  store ptr %t1, ptr %f.addr.0, align 8
  %t2 = load ptr, ptr %f.addr.0, align 8
  %t3 = icmp eq ptr %t2, null
  br i1 %t3, label %cond.then0.0, label %cond.end0
cond.then0.0:
  ret void
cond.end0:
  store ptr null, ptr %h.addr.4, align 8
  store i32 1, ptr %is-expr.addr.5, align 4
  %t6 = load ptr, ptr %f.addr.0, align 8
  %t7 = getelementptr inbounds %Node, ptr %t6, i32 0, i32 0
  %t8 = load i32, ptr %t7, align 4
  %t9 = icmp eq i32 %t8, 3
  store i1 %t9, ptr %and.val2, align 1
  br i1 %t9, label %and.rhs2, label %and.end2
and.rhs2:
  %t10 = load ptr, ptr %f.addr.0, align 8
  %t11 = call i32 @node-len(ptr %t10)
  %t12 = icmp ne i32 %t11, 0
  store i1 %t12, ptr %and.val3, align 1
  br i1 %t12, label %and.rhs3, label %and.end3
and.rhs3:
  %t13 = load ptr, ptr %f.addr.0, align 8
  %t14 = call ptr @node-at(ptr %t13, i32 0)
  %t15 = getelementptr inbounds %Node, ptr %t14, i32 0, i32 0
  %t16 = load i32, ptr %t15, align 4
  %t17 = icmp eq i32 %t16, 2
  store i1 %t17, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t18 = load i1, ptr %and.val3, align 1
  store i1 %t18, ptr %and.val2, align 1
  br label %and.end2
and.end2:
  %t19 = load i1, ptr %and.val2, align 1
  br i1 %t19, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t20 = load ptr, ptr %f.addr.0, align 8
  %t21 = call ptr @node-at(ptr %t20, i32 0)
  %t22 = getelementptr inbounds %Node, ptr %t21, i32 0, i32 3
  %t23 = load ptr, ptr %t22, align 8
  store ptr %t23, ptr %h.addr.4, align 8
  br label %cond.end1
cond.end1:
  %t24 = load ptr, ptr %h.addr.4, align 8
  %t25 = icmp ne ptr %t24, null
  store i1 %t25, ptr %and.val5, align 1
  br i1 %t25, label %and.rhs5, label %and.end5
and.rhs5:
  %t26 = load ptr, ptr %h.addr.4, align 8
  %t27 = getelementptr inbounds [9 x i8], ptr @.str.754, i64 0, i64 0
  %t28 = call i32 @strcmp(ptr %t26, ptr %t27)
  %t29 = icmp eq i32 %t28, 0
  store i1 %t29, ptr %and.val5, align 1
  br label %and.end5
and.end5:
  %t30 = load i1, ptr %and.val5, align 1
  br i1 %t30, label %cond.then4.0, label %cond.test4.1
cond.then4.0:
  %t31 = load ptr, ptr %f.addr.0, align 8
  call void @emit-defconst(ptr %t31)
  store i32 0, ptr %is-expr.addr.5, align 4
  br label %cond.end4
cond.test4.1:
  %t32 = load ptr, ptr %h.addr.4, align 8
  %t33 = icmp ne ptr %t32, null
  store i1 %t33, ptr %and.val6, align 1
  br i1 %t33, label %and.rhs6, label %and.end6
and.rhs6:
  %t34 = load ptr, ptr %h.addr.4, align 8
  %t35 = getelementptr inbounds [8 x i8], ptr @.str.755, i64 0, i64 0
  %t36 = call i32 @strcmp(ptr %t34, ptr %t35)
  %t37 = icmp eq i32 %t36, 0
  store i1 %t37, ptr %and.val6, align 1
  br label %and.end6
and.end6:
  %t38 = load i1, ptr %and.val6, align 1
  br i1 %t38, label %cond.then4.1, label %cond.test4.2
cond.then4.1:
  %t39 = load ptr, ptr %f.addr.0, align 8
  call void @emit-defenum(ptr %t39)
  store i32 0, ptr %is-expr.addr.5, align 4
  br label %cond.end4
cond.test4.2:
  %t40 = load ptr, ptr %h.addr.4, align 8
  %t41 = icmp ne ptr %t40, null
  store i1 %t41, ptr %and.val7, align 1
  br i1 %t41, label %and.rhs7, label %and.end7
and.rhs7:
  %t42 = load ptr, ptr %h.addr.4, align 8
  %t43 = getelementptr inbounds [7 x i8], ptr @.str.756, i64 0, i64 0
  %t44 = call i32 @strcmp(ptr %t42, ptr %t43)
  %t45 = icmp eq i32 %t44, 0
  store i1 %t45, ptr %and.val7, align 1
  br label %and.end7
and.end7:
  %t46 = load i1, ptr %and.val7, align 1
  br i1 %t46, label %cond.then4.2, label %cond.test4.3
cond.then4.2:
  call void @open-module-streams()
  %t47 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t47, ptr @g-out, align 8
  %t48 = load ptr, ptr %f.addr.0, align 8
  call void @emit-defvar(ptr %t48)
  %t49 = load ptr, ptr %f.addr.0, align 8
  %t50 = getelementptr inbounds %Node, ptr %t49, i32 0, i32 1
  %t51 = load i32, ptr %t50, align 4
  call void @repl-jit-module(i32 %t51)
  %t53 = load ptr, ptr %form.addr, align 8
  %t54 = call ptr @node-at(ptr %t53, i32 1)
  store ptr %t54, ptr %var-node.addr.52, align 8
  %t55 = load ptr, ptr %var-node.addr.52, align 8
  %t56 = icmp ne ptr %t55, null
  br i1 %t56, label %cond.then8.0, label %cond.end8
cond.then8.0:
  store ptr null, ptr %vname.addr.57, align 8
  store ptr null, ptr %vtype-name.addr.58, align 8
  %t59 = load ptr, ptr %var-node.addr.52, align 8
  call void @extract-name-type(ptr %t59, ptr %vname.addr.57, ptr %vtype-name.addr.58)
  %t60 = load ptr, ptr %vtype-name.addr.58, align 8
  %t61 = icmp ne ptr %t60, null
  br i1 %t61, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t63 = load ptr, ptr %vtype-name.addr.58, align 8
  %t64 = load ptr, ptr %var-node.addr.52, align 8
  %t65 = getelementptr inbounds %Node, ptr %t64, i32 0, i32 1
  %t66 = load i32, ptr %t65, align 4
  %t67 = call ptr @parse-type-name(ptr %t63, i32 %t66)
  store ptr %t67, ptr %vty.addr.62, align 8
  %t68 = load ptr, ptr @g-repl-preamble, align 8
  %t69 = getelementptr inbounds [26 x i8], ptr @.str.757, i64 0, i64 0
  %t70 = load ptr, ptr %vname.addr.57, align 8
  %t71 = call ptr @sanitize-for-ir(ptr %t70)
  %t72 = load ptr, ptr %vty.addr.62, align 8
  %t73 = call ptr @type-to-ir(ptr %t72)
  %t74 = call i32 (ptr, ptr, ...) @fprintf(ptr %t68, ptr %t69, ptr %t71, ptr %t73)
  br label %cond.end9
cond.end9:
  br label %cond.end8
cond.end8:
  %t75 = load ptr, ptr @stderr, align 8
  %t76 = getelementptr inbounds [11 x i8], ptr @.str.758, i64 0, i64 0
  %t77 = call i32 (ptr, ptr, ...) @fprintf(ptr %t75, ptr %t76)
  br label %cond.end4
cond.test4.3:
  %t78 = load ptr, ptr %h.addr.4, align 8
  %t79 = icmp ne ptr %t78, null
  store i1 %t79, ptr %and.val10, align 1
  br i1 %t79, label %and.rhs10, label %and.end10
and.rhs10:
  %t80 = load ptr, ptr %h.addr.4, align 8
  %t81 = getelementptr inbounds [10 x i8], ptr @.str.759, i64 0, i64 0
  %t82 = call i32 @strcmp(ptr %t80, ptr %t81)
  %t83 = icmp eq i32 %t82, 0
  store i1 %t83, ptr %and.val10, align 1
  br label %and.end10
and.end10:
  %t84 = load i1, ptr %and.val10, align 1
  br i1 %t84, label %cond.then4.3, label %cond.test4.4
cond.then4.3:
  call void @open-module-streams()
  %t85 = load ptr, ptr @g-type-stream, align 8
  store ptr %t85, ptr @g-out, align 8
  %t86 = load ptr, ptr %f.addr.0, align 8
  call void @emit-defstruct(ptr %t86)
  %t87 = load ptr, ptr @g-type-stream, align 8
  %t88 = call i32 @fclose(ptr %t87)
  %t89 = load ptr, ptr @g-decl-stream, align 8
  %t90 = call i32 @fclose(ptr %t89)
  %t91 = load ptr, ptr @g-def-stream, align 8
  %t92 = call i32 @fclose(ptr %t91)
  %t93 = load ptr, ptr @g-type-bufp, align 8
  %t94 = icmp ne ptr %t93, null
  store i1 %t94, ptr %and.val12, align 1
  br i1 %t94, label %and.rhs12, label %and.end12
and.rhs12:
  %t95 = load ptr, ptr @g-type-bufp, align 8
  %t96 = sext i32 0 to i64
  %t97 = call i32 @char-at(ptr %t95, i64 %t96)
  %t98 = icmp ne i32 %t97, 0
  store i1 %t98, ptr %and.val12, align 1
  br label %and.end12
and.end12:
  %t99 = load i1, ptr %and.val12, align 1
  br i1 %t99, label %cond.then11.0, label %cond.end11
cond.then11.0:
  %t100 = load ptr, ptr @g-type-bufp, align 8
  %t101 = load ptr, ptr @g-repl-preamble, align 8
  %t102 = call i32 @fputs(ptr %t100, ptr %t101)
  br label %cond.end11
cond.end11:
  %t103 = load ptr, ptr @g-type-bufp, align 8
  call void @free(ptr %t103)
  %t104 = load ptr, ptr @g-decl-bufp, align 8
  call void @free(ptr %t104)
  %t105 = load ptr, ptr @g-def-bufp, align 8
  call void @free(ptr %t105)
  %t106 = load ptr, ptr @stderr, align 8
  %t107 = getelementptr inbounds [11 x i8], ptr @.str.760, i64 0, i64 0
  %t108 = call i32 (ptr, ptr, ...) @fprintf(ptr %t106, ptr %t107)
  br label %cond.end4
cond.test4.4:
  %t109 = load ptr, ptr %h.addr.4, align 8
  %t110 = icmp ne ptr %t109, null
  store i1 %t110, ptr %and.val13, align 1
  br i1 %t110, label %and.rhs13, label %and.end13
and.rhs13:
  %t111 = load ptr, ptr %h.addr.4, align 8
  %t112 = getelementptr inbounds [8 x i8], ptr @.str.761, i64 0, i64 0
  %t113 = call i32 @strcmp(ptr %t111, ptr %t112)
  %t114 = icmp eq i32 %t113, 0
  store i1 %t114, ptr %and.val13, align 1
  br label %and.end13
and.end13:
  %t115 = load i1, ptr %and.val13, align 1
  br i1 %t115, label %cond.then4.4, label %cond.test4.5
cond.then4.4:
  call void @open-module-streams()
  %t116 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t116, ptr @g-out, align 8
  %t117 = load ptr, ptr %f.addr.0, align 8
  call void @emit-include(ptr %t117)
  %t118 = load ptr, ptr @g-type-stream, align 8
  %t119 = call i32 @fclose(ptr %t118)
  %t120 = load ptr, ptr @g-decl-stream, align 8
  %t121 = call i32 @fclose(ptr %t120)
  %t122 = load ptr, ptr @g-def-stream, align 8
  %t123 = call i32 @fclose(ptr %t122)
  %t124 = load ptr, ptr @g-decl-bufp, align 8
  %t125 = icmp ne ptr %t124, null
  store i1 %t125, ptr %and.val15, align 1
  br i1 %t125, label %and.rhs15, label %and.end15
and.rhs15:
  %t126 = load ptr, ptr @g-decl-bufp, align 8
  %t127 = sext i32 0 to i64
  %t128 = call i32 @char-at(ptr %t126, i64 %t127)
  %t129 = icmp ne i32 %t128, 0
  store i1 %t129, ptr %and.val15, align 1
  br label %and.end15
and.end15:
  %t130 = load i1, ptr %and.val15, align 1
  br i1 %t130, label %cond.then14.0, label %cond.end14
cond.then14.0:
  %t131 = load ptr, ptr @g-decl-bufp, align 8
  %t132 = load ptr, ptr @g-repl-preamble, align 8
  %t133 = call i32 @fputs(ptr %t131, ptr %t132)
  br label %cond.end14
cond.end14:
  %t134 = load ptr, ptr @g-type-bufp, align 8
  call void @free(ptr %t134)
  %t135 = load ptr, ptr @g-decl-bufp, align 8
  call void @free(ptr %t135)
  %t136 = load ptr, ptr @g-def-bufp, align 8
  call void @free(ptr %t136)
  br label %cond.end4
cond.test4.5:
  %t137 = load ptr, ptr %h.addr.4, align 8
  %t138 = icmp ne ptr %t137, null
  store i1 %t138, ptr %and.val16, align 1
  br i1 %t138, label %and.rhs16, label %and.end16
and.rhs16:
  %t139 = load ptr, ptr %h.addr.4, align 8
  %t140 = getelementptr inbounds [7 x i8], ptr @.str.762, i64 0, i64 0
  %t141 = call i32 @strcmp(ptr %t139, ptr %t140)
  %t142 = icmp eq i32 %t141, 0
  store i1 %t142, ptr %and.val16, align 1
  br label %and.end16
and.end16:
  %t143 = load i1, ptr %and.val16, align 1
  br i1 %t143, label %cond.then4.5, label %cond.test4.6
cond.then4.5:
  call void @open-module-streams()
  %t144 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t144, ptr @g-out, align 8
  %t145 = load ptr, ptr %f.addr.0, align 8
  call void @emit-extern(ptr %t145)
  %t146 = load ptr, ptr @g-type-stream, align 8
  %t147 = call i32 @fclose(ptr %t146)
  %t148 = load ptr, ptr @g-decl-stream, align 8
  %t149 = call i32 @fclose(ptr %t148)
  %t150 = load ptr, ptr @g-def-stream, align 8
  %t151 = call i32 @fclose(ptr %t150)
  %t152 = load ptr, ptr @g-decl-bufp, align 8
  %t153 = icmp ne ptr %t152, null
  store i1 %t153, ptr %and.val18, align 1
  br i1 %t153, label %and.rhs18, label %and.end18
and.rhs18:
  %t154 = load ptr, ptr @g-decl-bufp, align 8
  %t155 = sext i32 0 to i64
  %t156 = call i32 @char-at(ptr %t154, i64 %t155)
  %t157 = icmp ne i32 %t156, 0
  store i1 %t157, ptr %and.val18, align 1
  br label %and.end18
and.end18:
  %t158 = load i1, ptr %and.val18, align 1
  br i1 %t158, label %cond.then17.0, label %cond.end17
cond.then17.0:
  %t159 = load ptr, ptr @g-decl-bufp, align 8
  %t160 = load ptr, ptr @g-repl-preamble, align 8
  %t161 = call i32 @fputs(ptr %t159, ptr %t160)
  br label %cond.end17
cond.end17:
  %t162 = load ptr, ptr @g-type-bufp, align 8
  call void @free(ptr %t162)
  %t163 = load ptr, ptr @g-decl-bufp, align 8
  call void @free(ptr %t163)
  %t164 = load ptr, ptr @g-def-bufp, align 8
  call void @free(ptr %t164)
  br label %cond.end4
cond.test4.6:
  %t165 = load ptr, ptr %h.addr.4, align 8
  %t166 = icmp ne ptr %t165, null
  store i1 %t166, ptr %and.val19, align 1
  br i1 %t166, label %and.rhs19, label %and.end19
and.rhs19:
  %t167 = load ptr, ptr %h.addr.4, align 8
  %t168 = getelementptr inbounds [5 x i8], ptr @.str.763, i64 0, i64 0
  %t169 = call i32 @strcmp(ptr %t167, ptr %t168)
  %t170 = icmp eq i32 %t169, 0
  store i1 %t170, ptr %and.val19, align 1
  br label %and.end19
and.end19:
  %t171 = load i1, ptr %and.val19, align 1
  br i1 %t171, label %cond.then4.6, label %cond.test4.7
cond.then4.6:
  store i32 0, ptr %redef.addr.172, align 4
  %t174 = load ptr, ptr %form.addr, align 8
  %t175 = call ptr @node-at(ptr %t174, i32 1)
  store ptr %t175, ptr %name-node.addr.173, align 8
  %t176 = load ptr, ptr %name-node.addr.173, align 8
  %t177 = icmp ne ptr %t176, null
  br i1 %t177, label %cond.then20.0, label %cond.end20
cond.then20.0:
  store ptr null, ptr %fname.addr.178, align 8
  store ptr null, ptr %ret-name.addr.179, align 8
  %t180 = load ptr, ptr %name-node.addr.173, align 8
  call void @extract-name-type(ptr %t180, ptr %fname.addr.178, ptr %ret-name.addr.179)
  %t181 = load ptr, ptr @g-globals, align 8
  %t182 = load ptr, ptr %fname.addr.178, align 8
  %t183 = call ptr @scope-lookup(ptr %t181, ptr %t182)
  %t184 = icmp ne ptr %t183, null
  br i1 %t184, label %cond.then21.0, label %cond.end21
cond.then21.0:
  %t185 = load ptr, ptr @stderr, align 8
  %t186 = getelementptr inbounds [39 x i8], ptr @.str.764, i64 0, i64 0
  %t187 = load ptr, ptr %fname.addr.178, align 8
  %t188 = call i32 (ptr, ptr, ...) @fprintf(ptr %t185, ptr %t186, ptr %t187)
  store i32 1, ptr %redef.addr.172, align 4
  br label %cond.end21
cond.end21:
  br label %cond.end20
cond.end20:
  %t189 = load i32, ptr %redef.addr.172, align 4
  %t190 = icmp eq i32 %t189, 0
  br i1 %t190, label %cond.then22.0, label %cond.end22
cond.then22.0:
  call void @open-module-streams()
  %t192 = load ptr, ptr %form.addr, align 8
  %t193 = load ptr, ptr %f.addr.0, align 8
  %t194 = getelementptr inbounds %Node, ptr %t193, i32 0, i32 1
  %t195 = load i32, ptr %t194, align 4
  %t196 = call ptr @make-cell(ptr %t192, ptr null, i32 %t195)
  store ptr %t196, ptr %one-form.addr.191, align 8
  %t197 = load ptr, ptr %one-form.addr.191, align 8
  call void @prescan-defn-signatures(ptr %t197)
  %t198 = load ptr, ptr @g-def-stream, align 8
  store ptr %t198, ptr @g-out, align 8
  %t199 = load ptr, ptr %f.addr.0, align 8
  call void @emit-defn(ptr %t199)
  %t200 = load i32, ptr @g-qq-used, align 4
  %t201 = icmp ne i32 %t200, 0
  br i1 %t201, label %cond.then23.0, label %cond.end23
cond.then23.0:
  %t202 = load ptr, ptr @g-decl-stream, align 8
  %t203 = load ptr, ptr @g-def-stream, align 8
  call void @emit-qq-helpers(ptr %t202, ptr %t203)
  br label %cond.end23
cond.end23:
  %t204 = load ptr, ptr %f.addr.0, align 8
  %t205 = getelementptr inbounds %Node, ptr %t204, i32 0, i32 1
  %t206 = load i32, ptr %t205, align 4
  call void @repl-jit-module(i32 %t206)
  store i32 0, ptr @g-qq-used, align 4
  %t208 = load ptr, ptr %form.addr, align 8
  %t209 = call ptr @node-at(ptr %t208, i32 1)
  store ptr %t209, ptr %name-node2.addr.207, align 8
  %t210 = load ptr, ptr %name-node2.addr.207, align 8
  %t211 = icmp ne ptr %t210, null
  br i1 %t211, label %cond.then24.0, label %cond.end24
cond.then24.0:
  store ptr null, ptr %fname2.addr.212, align 8
  store ptr null, ptr %ret-name2.addr.213, align 8
  %t214 = load ptr, ptr %name-node2.addr.207, align 8
  call void @extract-name-type(ptr %t214, ptr %fname2.addr.212, ptr %ret-name2.addr.213)
  %t216 = load ptr, ptr @g-globals, align 8
  %t217 = load ptr, ptr %fname2.addr.212, align 8
  %t218 = call ptr @scope-lookup(ptr %t216, ptr %t217)
  store ptr %t218, ptr %sym.addr.215, align 8
  %t219 = load ptr, ptr %sym.addr.215, align 8
  %t220 = icmp ne ptr %t219, null
  br i1 %t220, label %cond.then25.0, label %cond.end25
cond.then25.0:
  %t222 = load ptr, ptr %sym.addr.215, align 8
  %t223 = getelementptr inbounds %Sym, ptr %t222, i32 0, i32 1
  %t224 = load ptr, ptr %t223, align 8
  store ptr %t224, ptr %ft.addr.221, align 8
  %t225 = load ptr, ptr %ft.addr.221, align 8
  %t226 = getelementptr inbounds %Type, ptr %t225, i32 0, i32 0
  %t227 = load i32, ptr %t226, align 4
  %t228 = icmp eq i32 %t227, 11
  br i1 %t228, label %cond.then26.0, label %cond.end26
cond.then26.0:
  %t229 = load ptr, ptr @g-repl-preamble, align 8
  %t230 = getelementptr inbounds [16 x i8], ptr @.str.765, i64 0, i64 0
  %t231 = load ptr, ptr %ft.addr.221, align 8
  %t232 = getelementptr inbounds %Type, ptr %t231, i32 0, i32 1
  %t233 = load ptr, ptr %t232, align 8
  %t234 = call ptr @type-to-ir(ptr %t233)
  %t235 = load ptr, ptr %fname2.addr.212, align 8
  %t236 = call ptr @sanitize-for-ir(ptr %t235)
  %t237 = call i32 (ptr, ptr, ...) @fprintf(ptr %t229, ptr %t230, ptr %t234, ptr %t236)
  store i32 0, ptr %pi.addr.238, align 4
  br label %while.cond27
while.cond27:
  %t239 = load i32, ptr %pi.addr.238, align 4
  %t240 = load ptr, ptr %ft.addr.221, align 8
  %t241 = getelementptr inbounds %Type, ptr %t240, i32 0, i32 3
  %t242 = load i32, ptr %t241, align 4
  %t243 = icmp slt i32 %t239, %t242
  br i1 %t243, label %while.body27, label %while.end27
while.body27:
  %t244 = load i32, ptr %pi.addr.238, align 4
  %t245 = icmp ne i32 %t244, 0
  br i1 %t245, label %cond.then28.0, label %cond.end28
cond.then28.0:
  %t246 = load ptr, ptr @g-repl-preamble, align 8
  %t247 = getelementptr inbounds [3 x i8], ptr @.str.766, i64 0, i64 0
  %t248 = call i32 (ptr, ptr, ...) @fprintf(ptr %t246, ptr %t247)
  br label %cond.end28
cond.end28:
  %t249 = load ptr, ptr @g-repl-preamble, align 8
  %t250 = getelementptr inbounds [3 x i8], ptr @.str.767, i64 0, i64 0
  %t251 = load ptr, ptr %ft.addr.221, align 8
  %t252 = getelementptr inbounds %Type, ptr %t251, i32 0, i32 2
  %t253 = load ptr, ptr %t252, align 8
  %t254 = load i32, ptr %pi.addr.238, align 4
  %t255 = sext i32 %t254 to i64
  %t256 = getelementptr inbounds ptr, ptr %t253, i64 %t255
  %t257 = load ptr, ptr %t256, align 8
  %t258 = call ptr @type-to-ir(ptr %t257)
  %t259 = call i32 (ptr, ptr, ...) @fprintf(ptr %t249, ptr %t250, ptr %t258)
  %t260 = load i32, ptr %pi.addr.238, align 4
  %t261 = add nsw i32 %t260, 1
  store i32 %t261, ptr %pi.addr.238, align 4
  br label %while.cond27
while.end27:
  %t262 = load ptr, ptr %ft.addr.221, align 8
  %t263 = getelementptr inbounds %Type, ptr %t262, i32 0, i32 4
  %t264 = load i32, ptr %t263, align 4
  %t265 = icmp ne i32 %t264, 0
  br i1 %t265, label %cond.then29.0, label %cond.end29
cond.then29.0:
  %t267 = getelementptr inbounds [1 x i8], ptr @.str.768, i64 0, i64 0
  store ptr %t267, ptr %sep.addr.266, align 8
  %t268 = load ptr, ptr %ft.addr.221, align 8
  %t269 = getelementptr inbounds %Type, ptr %t268, i32 0, i32 3
  %t270 = load i32, ptr %t269, align 4
  %t271 = icmp ne i32 %t270, 0
  br i1 %t271, label %cond.then30.0, label %cond.end30
cond.then30.0:
  %t272 = getelementptr inbounds [3 x i8], ptr @.str.769, i64 0, i64 0
  store ptr %t272, ptr %sep.addr.266, align 8
  br label %cond.end30
cond.end30:
  %t273 = load ptr, ptr @g-repl-preamble, align 8
  %t274 = getelementptr inbounds [6 x i8], ptr @.str.770, i64 0, i64 0
  %t275 = load ptr, ptr %sep.addr.266, align 8
  %t276 = call i32 (ptr, ptr, ...) @fprintf(ptr %t273, ptr %t274, ptr %t275)
  br label %cond.end29
cond.end29:
  %t277 = load ptr, ptr @g-repl-preamble, align 8
  %t278 = getelementptr inbounds [3 x i8], ptr @.str.771, i64 0, i64 0
  %t279 = call i32 (ptr, ptr, ...) @fprintf(ptr %t277, ptr %t278)
  br label %cond.end26
cond.end26:
  br label %cond.end25
cond.end25:
  br label %cond.end24
cond.end24:
  %t280 = load ptr, ptr @stderr, align 8
  %t281 = getelementptr inbounds [11 x i8], ptr @.str.772, i64 0, i64 0
  %t282 = call i32 (ptr, ptr, ...) @fprintf(ptr %t280, ptr %t281)
  br label %cond.end22
cond.end22:
  br label %cond.end4
cond.test4.7:
  %t283 = load ptr, ptr %h.addr.4, align 8
  %t284 = icmp ne ptr %t283, null
  store i1 %t284, ptr %and.val31, align 1
  br i1 %t284, label %and.rhs31, label %and.end31
and.rhs31:
  %t285 = load ptr, ptr %h.addr.4, align 8
  %t286 = getelementptr inbounds [13 x i8], ptr @.str.773, i64 0, i64 0
  %t287 = call i32 @strcmp(ptr %t285, ptr %t286)
  %t288 = icmp eq i32 %t287, 0
  store i1 %t288, ptr %and.val31, align 1
  br label %and.end31
and.end31:
  %t289 = load i1, ptr %and.val31, align 1
  br i1 %t289, label %cond.then4.7, label %cond.test4.8
cond.then4.7:
  call void @open-module-streams()
  %t290 = load ptr, ptr %f.addr.0, align 8
  call void @emit-compile-time(ptr %t290)
  br label %cond.end4
cond.test4.8:
  %t291 = load ptr, ptr %h.addr.4, align 8
  %t292 = icmp ne ptr %t291, null
  store i1 %t292, ptr %and.val32, align 1
  br i1 %t292, label %and.rhs32, label %and.end32
and.rhs32:
  %t293 = load ptr, ptr %h.addr.4, align 8
  %t294 = getelementptr inbounds [9 x i8], ptr @.str.774, i64 0, i64 0
  %t295 = call i32 @strcmp(ptr %t293, ptr %t294)
  %t296 = icmp eq i32 %t295, 0
  store i1 %t296, ptr %and.val32, align 1
  br label %and.end32
and.end32:
  %t297 = load i1, ptr %and.val32, align 1
  br i1 %t297, label %cond.then4.8, label %cond.test4.9
cond.then4.8:
  %t298 = load ptr, ptr %f.addr.0, align 8
  call void @emit-defmacro(ptr %t298)
  %t299 = load ptr, ptr @stderr, align 8
  %t300 = getelementptr inbounds [11 x i8], ptr @.str.775, i64 0, i64 0
  %t301 = call i32 (ptr, ptr, ...) @fprintf(ptr %t299, ptr %t300)
  br label %cond.end4
cond.test4.9:
  %t302 = load ptr, ptr %h.addr.4, align 8
  %t303 = icmp ne ptr %t302, null
  store i1 %t303, ptr %and.val33, align 1
  br i1 %t303, label %and.rhs33, label %and.end33
and.rhs33:
  %t304 = load ptr, ptr %h.addr.4, align 8
  %t305 = getelementptr inbounds [11 x i8], ptr @.str.776, i64 0, i64 0
  %t306 = call i32 @strcmp(ptr %t304, ptr %t305)
  %t307 = icmp eq i32 %t306, 0
  store i1 %t307, ptr %and.val33, align 1
  br label %and.end33
and.end33:
  %t308 = load i1, ptr %and.val33, align 1
  br i1 %t308, label %cond.then4.9, label %cond.test4.10
cond.then4.9:
  %t309 = load ptr, ptr %f.addr.0, align 8
  call void @emit-def-rmacro(ptr %t309)
  %t310 = load ptr, ptr @stderr, align 8
  %t311 = getelementptr inbounds [11 x i8], ptr @.str.777, i64 0, i64 0
  %t312 = call i32 (ptr, ptr, ...) @fprintf(ptr %t310, ptr %t311)
  br label %cond.end4
cond.test4.10:
  %t313 = load ptr, ptr %h.addr.4, align 8
  %t314 = icmp ne ptr %t313, null
  store i1 %t314, ptr %and.val34, align 1
  br i1 %t314, label %and.rhs34, label %and.end34
and.rhs34:
  %t315 = load ptr, ptr %h.addr.4, align 8
  %t316 = getelementptr inbounds [7 x i8], ptr @.str.778, i64 0, i64 0
  %t317 = call i32 @strcmp(ptr %t315, ptr %t316)
  %t318 = icmp eq i32 %t317, 0
  store i1 %t318, ptr %and.val34, align 1
  br label %and.end34
and.end34:
  %t319 = load i1, ptr %and.val34, align 1
  br i1 %t319, label %cond.then4.10, label %cond.test4.11
cond.then4.10:
  %t321 = load ptr, ptr @g-globals, align 8
  %t322 = getelementptr inbounds %Scope, ptr %t321, i32 0, i32 2
  %t323 = load i32, ptr %t322, align 4
  store i32 %t323, ptr %pre-len.addr.320, align 4
  call void @open-module-streams()
  %t324 = load ptr, ptr %f.addr.0, align 8
  call void @emit-import(ptr %t324)
  %t325 = load ptr, ptr @g-type-stream, align 8
  %t326 = call i32 @fflush(ptr %t325)
  %t327 = load ptr, ptr @g-type-bufp, align 8
  %t328 = icmp ne ptr %t327, null
  store i1 %t328, ptr %and.val36, align 1
  br i1 %t328, label %and.rhs36, label %and.end36
and.rhs36:
  %t329 = load ptr, ptr @g-type-bufp, align 8
  %t330 = sext i32 0 to i64
  %t331 = call i32 @char-at(ptr %t329, i64 %t330)
  %t332 = icmp ne i32 %t331, 0
  store i1 %t332, ptr %and.val36, align 1
  br label %and.end36
and.end36:
  %t333 = load i1, ptr %and.val36, align 1
  br i1 %t333, label %cond.then35.0, label %cond.end35
cond.then35.0:
  %t334 = load ptr, ptr @g-type-bufp, align 8
  %t335 = load ptr, ptr @g-repl-preamble, align 8
  %t336 = call i32 @fputs(ptr %t334, ptr %t335)
  br label %cond.end35
cond.end35:
  %t337 = load ptr, ptr %f.addr.0, align 8
  %t338 = getelementptr inbounds %Node, ptr %t337, i32 0, i32 1
  %t339 = load i32, ptr %t338, align 4
  call void @repl-jit-module(i32 %t339)
  %t341 = load i32, ptr %pre-len.addr.320, align 4
  store i32 %t341, ptr %si.addr.340, align 4
  br label %while.cond37
while.cond37:
  %t342 = load i32, ptr %si.addr.340, align 4
  %t343 = load ptr, ptr @g-globals, align 8
  %t344 = getelementptr inbounds %Scope, ptr %t343, i32 0, i32 2
  %t345 = load i32, ptr %t344, align 4
  %t346 = icmp slt i32 %t342, %t345
  br i1 %t346, label %while.body37, label %while.end37
while.body37:
  %t348 = load ptr, ptr @g-globals, align 8
  %t349 = getelementptr inbounds %Scope, ptr %t348, i32 0, i32 1
  %t350 = load ptr, ptr %t349, align 8
  %t351 = load i32, ptr %si.addr.340, align 4
  %t352 = sext i32 %t351 to i64
  %t353 = getelementptr inbounds %Sym, ptr %t350, i64 %t352
  store ptr %t353, ptr %sym.addr.347, align 8
  %t355 = load ptr, ptr %sym.addr.347, align 8
  %t356 = getelementptr inbounds %Sym, ptr %t355, i32 0, i32 1
  %t357 = load ptr, ptr %t356, align 8
  store ptr %t357, ptr %ft.addr.354, align 8
  %t358 = load ptr, ptr %ft.addr.354, align 8
  %t359 = getelementptr inbounds %Type, ptr %t358, i32 0, i32 0
  %t360 = load i32, ptr %t359, align 4
  %t361 = icmp eq i32 %t360, 11
  br i1 %t361, label %cond.then38.0, label %cond.end38
cond.then38.0:
  store i32 0, ptr %is-dup.addr.362, align 4
  %t364 = load i32, ptr %si.addr.340, align 4
  %t365 = add nsw i32 %t364, 1
  store i32 %t365, ptr %dj.addr.363, align 4
  br label %while.cond39
while.cond39:
  %t366 = load i32, ptr %dj.addr.363, align 4
  %t367 = load ptr, ptr @g-globals, align 8
  %t368 = getelementptr inbounds %Scope, ptr %t367, i32 0, i32 2
  %t369 = load i32, ptr %t368, align 4
  %t370 = icmp slt i32 %t366, %t369
  br i1 %t370, label %while.body39, label %while.end39
while.body39:
  %t372 = load ptr, ptr @g-globals, align 8
  %t373 = getelementptr inbounds %Scope, ptr %t372, i32 0, i32 1
  %t374 = load ptr, ptr %t373, align 8
  %t375 = load i32, ptr %dj.addr.363, align 4
  %t376 = sext i32 %t375 to i64
  %t377 = getelementptr inbounds %Sym, ptr %t374, i64 %t376
  store ptr %t377, ptr %nxt.addr.371, align 8
  %t378 = load ptr, ptr %nxt.addr.371, align 8
  %t379 = getelementptr inbounds %Sym, ptr %t378, i32 0, i32 0
  %t380 = load ptr, ptr %t379, align 8
  %t381 = load ptr, ptr %sym.addr.347, align 8
  %t382 = getelementptr inbounds %Sym, ptr %t381, i32 0, i32 0
  %t383 = load ptr, ptr %t382, align 8
  %t384 = call i32 @strcmp(ptr %t380, ptr %t383)
  %t385 = icmp eq i32 %t384, 0
  br i1 %t385, label %cond.then40.0, label %cond.end40
cond.then40.0:
  store i32 1, ptr %is-dup.addr.362, align 4
  br label %cond.end40
cond.end40:
  %t386 = load i32, ptr %dj.addr.363, align 4
  %t387 = add nsw i32 %t386, 1
  store i32 %t387, ptr %dj.addr.363, align 4
  br label %while.cond39
while.end39:
  %t388 = load i32, ptr %is-dup.addr.362, align 4
  %t389 = icmp eq i32 %t388, 0
  br i1 %t389, label %cond.then41.0, label %cond.end41
cond.then41.0:
  %t390 = load ptr, ptr @g-repl-preamble, align 8
  %t391 = getelementptr inbounds [15 x i8], ptr @.str.779, i64 0, i64 0
  %t392 = load ptr, ptr %ft.addr.354, align 8
  %t393 = getelementptr inbounds %Type, ptr %t392, i32 0, i32 1
  %t394 = load ptr, ptr %t393, align 8
  %t395 = call ptr @type-to-ir(ptr %t394)
  %t396 = load ptr, ptr %sym.addr.347, align 8
  %t397 = getelementptr inbounds %Sym, ptr %t396, i32 0, i32 2
  %t398 = load ptr, ptr %t397, align 8
  %t399 = call i32 (ptr, ptr, ...) @fprintf(ptr %t390, ptr %t391, ptr %t395, ptr %t398)
  store i32 0, ptr %pi.addr.400, align 4
  br label %while.cond42
while.cond42:
  %t401 = load i32, ptr %pi.addr.400, align 4
  %t402 = load ptr, ptr %ft.addr.354, align 8
  %t403 = getelementptr inbounds %Type, ptr %t402, i32 0, i32 3
  %t404 = load i32, ptr %t403, align 4
  %t405 = icmp slt i32 %t401, %t404
  br i1 %t405, label %while.body42, label %while.end42
while.body42:
  %t406 = load i32, ptr %pi.addr.400, align 4
  %t407 = icmp ne i32 %t406, 0
  br i1 %t407, label %cond.then43.0, label %cond.end43
cond.then43.0:
  %t408 = load ptr, ptr @g-repl-preamble, align 8
  %t409 = getelementptr inbounds [3 x i8], ptr @.str.780, i64 0, i64 0
  %t410 = call i32 (ptr, ptr, ...) @fprintf(ptr %t408, ptr %t409)
  br label %cond.end43
cond.end43:
  %t411 = load ptr, ptr @g-repl-preamble, align 8
  %t412 = getelementptr inbounds [3 x i8], ptr @.str.781, i64 0, i64 0
  %t413 = load ptr, ptr %ft.addr.354, align 8
  %t414 = getelementptr inbounds %Type, ptr %t413, i32 0, i32 2
  %t415 = load ptr, ptr %t414, align 8
  %t416 = load i32, ptr %pi.addr.400, align 4
  %t417 = sext i32 %t416 to i64
  %t418 = getelementptr inbounds ptr, ptr %t415, i64 %t417
  %t419 = load ptr, ptr %t418, align 8
  %t420 = call ptr @type-to-ir(ptr %t419)
  %t421 = call i32 (ptr, ptr, ...) @fprintf(ptr %t411, ptr %t412, ptr %t420)
  %t422 = load i32, ptr %pi.addr.400, align 4
  %t423 = add nsw i32 %t422, 1
  store i32 %t423, ptr %pi.addr.400, align 4
  br label %while.cond42
while.end42:
  %t424 = load ptr, ptr %ft.addr.354, align 8
  %t425 = getelementptr inbounds %Type, ptr %t424, i32 0, i32 4
  %t426 = load i32, ptr %t425, align 4
  %t427 = icmp ne i32 %t426, 0
  br i1 %t427, label %cond.then44.0, label %cond.end44
cond.then44.0:
  %t429 = getelementptr inbounds [1 x i8], ptr @.str.782, i64 0, i64 0
  store ptr %t429, ptr %sep.addr.428, align 8
  %t430 = load ptr, ptr %ft.addr.354, align 8
  %t431 = getelementptr inbounds %Type, ptr %t430, i32 0, i32 3
  %t432 = load i32, ptr %t431, align 4
  %t433 = icmp ne i32 %t432, 0
  br i1 %t433, label %cond.then45.0, label %cond.end45
cond.then45.0:
  %t434 = getelementptr inbounds [3 x i8], ptr @.str.783, i64 0, i64 0
  store ptr %t434, ptr %sep.addr.428, align 8
  br label %cond.end45
cond.end45:
  %t435 = load ptr, ptr @g-repl-preamble, align 8
  %t436 = getelementptr inbounds [6 x i8], ptr @.str.784, i64 0, i64 0
  %t437 = load ptr, ptr %sep.addr.428, align 8
  %t438 = call i32 (ptr, ptr, ...) @fprintf(ptr %t435, ptr %t436, ptr %t437)
  br label %cond.end44
cond.end44:
  %t439 = load ptr, ptr @g-repl-preamble, align 8
  %t440 = getelementptr inbounds [3 x i8], ptr @.str.785, i64 0, i64 0
  %t441 = call i32 (ptr, ptr, ...) @fprintf(ptr %t439, ptr %t440)
  br label %cond.end41
cond.end41:
  br label %cond.end38
cond.end38:
  %t442 = load i32, ptr %si.addr.340, align 4
  %t443 = add nsw i32 %t442, 1
  store i32 %t443, ptr %si.addr.340, align 4
  br label %while.cond37
while.end37:
  br label %cond.end4
cond.test4.11:
  br i1 1, label %cond.then4.11, label %cond.end4
cond.then4.11:
  call void @open-module-streams()
  %t445 = getelementptr inbounds [16 x i8], ptr @.str.786, i64 0, i64 0
  %t446 = load i32, ptr @g-repl-id, align 4
  %t447 = sext i32 %t446 to i64
  %t448 = call ptr @fmt-i64(ptr %t445, i64 %t447)
  store ptr %t448, ptr %eval-sym.addr.444, align 8
  %t449 = load i32, ptr @g-repl-id, align 4
  %t450 = add nsw i32 %t449, 1
  store i32 %t450, ptr @g-repl-id, align 4
  %t451 = load ptr, ptr @g-def-stream, align 8
  store ptr %t451, ptr @g-out, align 8
  call void @reset-function-state()
  %t453 = load ptr, ptr @g-globals, align 8
  %t454 = call ptr @scope-new(ptr %t453)
  store ptr %t454, ptr %fn-scope.addr.452, align 8
  %t456 = load ptr, ptr %f.addr.0, align 8
  %t457 = load ptr, ptr %fn-scope.addr.452, align 8
  %t458 = call ptr @emit-node(ptr %t456, ptr %t457)
  store ptr %t458, ptr %result.addr.455, align 8
  %t460 = load ptr, ptr %result.addr.455, align 8
  %t461 = getelementptr inbounds %Val, ptr %t460, i32 0, i32 0
  %t462 = load ptr, ptr %t461, align 8
  %t463 = getelementptr inbounds %Type, ptr %t462, i32 0, i32 0
  %t464 = load i32, ptr %t463, align 4
  store i32 %t464, ptr %result-kind.addr.459, align 4
  %t465 = load i32, ptr @g-block-term, align 4
  %t466 = icmp eq i32 %t465, 0
  br i1 %t466, label %cond.then46.0, label %cond.end46
cond.then46.0:
  %t467 = load i32, ptr %result-kind.addr.459, align 4
  %t468 = icmp eq i32 %t467, 0
  br i1 %t468, label %cond.then47.0, label %cond.test47.1
cond.then47.0:
  %t469 = load ptr, ptr @g-body-stream, align 8
  %t470 = getelementptr inbounds [12 x i8], ptr @.str.787, i64 0, i64 0
  %t471 = call i32 (ptr, ptr, ...) @fprintf(ptr %t469, ptr %t470)
  br label %cond.end47
cond.test47.1:
  %t472 = load i32, ptr %result-kind.addr.459, align 4
  %t473 = icmp eq i32 %t472, 4
  store i1 %t473, ptr %or.val48, align 1
  br i1 %t473, label %or.end48, label %or.rhs48
or.rhs48:
  %t474 = load i32, ptr %result-kind.addr.459, align 4
  %t475 = icmp eq i32 %t474, 1
  store i1 %t475, ptr %or.val49, align 1
  br i1 %t475, label %or.end49, label %or.rhs49
or.rhs49:
  %t476 = load i32, ptr %result-kind.addr.459, align 4
  %t477 = icmp eq i32 %t476, 2
  store i1 %t477, ptr %or.val50, align 1
  br i1 %t477, label %or.end50, label %or.rhs50
or.rhs50:
  %t478 = load i32, ptr %result-kind.addr.459, align 4
  %t479 = icmp eq i32 %t478, 3
  store i1 %t479, ptr %or.val50, align 1
  br label %or.end50
or.end50:
  %t480 = load i1, ptr %or.val50, align 1
  store i1 %t480, ptr %or.val49, align 1
  br label %or.end49
or.end49:
  %t481 = load i1, ptr %or.val49, align 1
  store i1 %t481, ptr %or.val48, align 1
  br label %or.end48
or.end48:
  %t482 = load i1, ptr %or.val48, align 1
  br i1 %t482, label %cond.then47.1, label %cond.test47.2
cond.then47.1:
  %t484 = load ptr, ptr %result.addr.455, align 8
  %t485 = getelementptr inbounds %Val, ptr %t484, i32 0, i32 1
  %t486 = load ptr, ptr %t485, align 8
  store ptr %t486, ptr %ret-val.addr.483, align 8
  %t487 = load i32, ptr %result-kind.addr.459, align 4
  %t488 = icmp ne i32 %t487, 4
  br i1 %t488, label %cond.then51.0, label %cond.end51
cond.then51.0:
  %t490 = call ptr @new-tmp()
  store ptr %t490, ptr %ext-tmp.addr.489, align 8
  %t491 = load i32, ptr %result-kind.addr.459, align 4
  %t492 = icmp eq i32 %t491, 1
  br i1 %t492, label %cond.then52.0, label %cond.test52.1
cond.then52.0:
  %t493 = load ptr, ptr @g-body-stream, align 8
  %t494 = getelementptr inbounds [26 x i8], ptr @.str.788, i64 0, i64 0
  %t495 = load ptr, ptr %ext-tmp.addr.489, align 8
  %t496 = load ptr, ptr %result.addr.455, align 8
  %t497 = getelementptr inbounds %Val, ptr %t496, i32 0, i32 1
  %t498 = load ptr, ptr %t497, align 8
  %t499 = call i32 (ptr, ptr, ...) @fprintf(ptr %t493, ptr %t494, ptr %t495, ptr %t498)
  br label %cond.end52
cond.test52.1:
  %t500 = load i32, ptr %result-kind.addr.459, align 4
  %t501 = icmp eq i32 %t500, 2
  br i1 %t501, label %cond.then52.1, label %cond.test52.2
cond.then52.1:
  %t502 = load ptr, ptr @g-body-stream, align 8
  %t503 = getelementptr inbounds [26 x i8], ptr @.str.789, i64 0, i64 0
  %t504 = load ptr, ptr %ext-tmp.addr.489, align 8
  %t505 = load ptr, ptr %result.addr.455, align 8
  %t506 = getelementptr inbounds %Val, ptr %t505, i32 0, i32 1
  %t507 = load ptr, ptr %t506, align 8
  %t508 = call i32 (ptr, ptr, ...) @fprintf(ptr %t502, ptr %t503, ptr %t504, ptr %t507)
  br label %cond.end52
cond.test52.2:
  %t509 = load i32, ptr %result-kind.addr.459, align 4
  %t510 = icmp eq i32 %t509, 3
  br i1 %t510, label %cond.then52.2, label %cond.test52.3
cond.then52.2:
  %t511 = load ptr, ptr @g-body-stream, align 8
  %t512 = getelementptr inbounds [27 x i8], ptr @.str.790, i64 0, i64 0
  %t513 = load ptr, ptr %ext-tmp.addr.489, align 8
  %t514 = load ptr, ptr %result.addr.455, align 8
  %t515 = getelementptr inbounds %Val, ptr %t514, i32 0, i32 1
  %t516 = load ptr, ptr %t515, align 8
  %t517 = call i32 (ptr, ptr, ...) @fprintf(ptr %t511, ptr %t512, ptr %t513, ptr %t516)
  br label %cond.end52
cond.test52.3:
  br i1 1, label %cond.then52.3, label %cond.end52
cond.then52.3:
  br label %cond.end52
cond.end52:
  %t518 = load ptr, ptr %ext-tmp.addr.489, align 8
  store ptr %t518, ptr %ret-val.addr.483, align 8
  br label %cond.end51
cond.end51:
  %t519 = load ptr, ptr @g-body-stream, align 8
  %t520 = getelementptr inbounds [14 x i8], ptr @.str.791, i64 0, i64 0
  %t521 = load ptr, ptr %ret-val.addr.483, align 8
  %t522 = call i32 (ptr, ptr, ...) @fprintf(ptr %t519, ptr %t520, ptr %t521)
  br label %cond.end47
cond.test47.2:
  %t523 = load i32, ptr %result-kind.addr.459, align 4
  %t524 = icmp eq i32 %t523, 5
  br i1 %t524, label %cond.then47.2, label %cond.test47.3
cond.then47.2:
  %t525 = load ptr, ptr @g-body-stream, align 8
  %t526 = getelementptr inbounds [14 x i8], ptr @.str.792, i64 0, i64 0
  %t527 = load ptr, ptr %result.addr.455, align 8
  %t528 = getelementptr inbounds %Val, ptr %t527, i32 0, i32 1
  %t529 = load ptr, ptr %t528, align 8
  %t530 = call i32 (ptr, ptr, ...) @fprintf(ptr %t525, ptr %t526, ptr %t529)
  br label %cond.end47
cond.test47.3:
  %t531 = load i32, ptr %result-kind.addr.459, align 4
  %t532 = icmp eq i32 %t531, 10
  br i1 %t532, label %cond.then47.3, label %cond.test47.4
cond.then47.3:
  %t533 = load ptr, ptr @g-body-stream, align 8
  %t534 = getelementptr inbounds [14 x i8], ptr @.str.793, i64 0, i64 0
  %t535 = load ptr, ptr %result.addr.455, align 8
  %t536 = getelementptr inbounds %Val, ptr %t535, i32 0, i32 1
  %t537 = load ptr, ptr %t536, align 8
  %t538 = call i32 (ptr, ptr, ...) @fprintf(ptr %t533, ptr %t534, ptr %t537)
  br label %cond.end47
cond.test47.4:
  br i1 1, label %cond.then47.4, label %cond.end47
cond.then47.4:
  %t539 = load ptr, ptr @g-body-stream, align 8
  %t540 = getelementptr inbounds [12 x i8], ptr @.str.794, i64 0, i64 0
  %t541 = call i32 (ptr, ptr, ...) @fprintf(ptr %t539, ptr %t540)
  br label %cond.end47
cond.end47:
  br label %cond.end46
cond.end46:
  %t542 = load ptr, ptr @g-entry-stream, align 8
  %t543 = call i32 @fclose(ptr %t542)
  %t544 = load ptr, ptr @g-body-stream, align 8
  %t545 = call i32 @fclose(ptr %t544)
  %t547 = getelementptr inbounds [5 x i8], ptr @.str.795, i64 0, i64 0
  store ptr %t547, ptr %ret-ir.addr.546, align 8
  %t548 = load i32, ptr %result-kind.addr.459, align 4
  %t549 = icmp eq i32 %t548, 4
  store i1 %t549, ptr %or.val54, align 1
  br i1 %t549, label %or.end54, label %or.rhs54
or.rhs54:
  %t550 = load i32, ptr %result-kind.addr.459, align 4
  %t551 = icmp eq i32 %t550, 1
  store i1 %t551, ptr %or.val55, align 1
  br i1 %t551, label %or.end55, label %or.rhs55
or.rhs55:
  %t552 = load i32, ptr %result-kind.addr.459, align 4
  %t553 = icmp eq i32 %t552, 2
  store i1 %t553, ptr %or.val56, align 1
  br i1 %t553, label %or.end56, label %or.rhs56
or.rhs56:
  %t554 = load i32, ptr %result-kind.addr.459, align 4
  %t555 = icmp eq i32 %t554, 3
  store i1 %t555, ptr %or.val56, align 1
  br label %or.end56
or.end56:
  %t556 = load i1, ptr %or.val56, align 1
  store i1 %t556, ptr %or.val55, align 1
  br label %or.end55
or.end55:
  %t557 = load i1, ptr %or.val55, align 1
  store i1 %t557, ptr %or.val54, align 1
  br label %or.end54
or.end54:
  %t558 = load i1, ptr %or.val54, align 1
  br i1 %t558, label %cond.then53.0, label %cond.end53
cond.then53.0:
  %t559 = getelementptr inbounds [4 x i8], ptr @.str.796, i64 0, i64 0
  store ptr %t559, ptr %ret-ir.addr.546, align 8
  br label %cond.end53
cond.end53:
  %t560 = load i32, ptr %result-kind.addr.459, align 4
  %t561 = icmp eq i32 %t560, 5
  br i1 %t561, label %cond.then57.0, label %cond.end57
cond.then57.0:
  %t562 = getelementptr inbounds [4 x i8], ptr @.str.797, i64 0, i64 0
  store ptr %t562, ptr %ret-ir.addr.546, align 8
  br label %cond.end57
cond.end57:
  %t563 = load i32, ptr %result-kind.addr.459, align 4
  %t564 = icmp eq i32 %t563, 10
  br i1 %t564, label %cond.then58.0, label %cond.end58
cond.then58.0:
  %t565 = getelementptr inbounds [4 x i8], ptr @.str.798, i64 0, i64 0
  store ptr %t565, ptr %ret-ir.addr.546, align 8
  br label %cond.end58
cond.end58:
  %t566 = load ptr, ptr @g-def-stream, align 8
  %t567 = getelementptr inbounds [19 x i8], ptr @.str.799, i64 0, i64 0
  %t568 = load ptr, ptr %ret-ir.addr.546, align 8
  %t569 = load ptr, ptr %eval-sym.addr.444, align 8
  %t570 = call i32 (ptr, ptr, ...) @fprintf(ptr %t566, ptr %t567, ptr %t568, ptr %t569)
  %t571 = load ptr, ptr @g-def-stream, align 8
  %t572 = getelementptr inbounds [8 x i8], ptr @.str.800, i64 0, i64 0
  %t573 = call i32 (ptr, ptr, ...) @fprintf(ptr %t571, ptr %t572)
  %t574 = load ptr, ptr @g-entry-bufp, align 8
  %t575 = icmp ne ptr %t574, null
  store i1 %t575, ptr %and.val60, align 1
  br i1 %t575, label %and.rhs60, label %and.end60
and.rhs60:
  %t576 = load ptr, ptr @g-entry-bufp, align 8
  %t577 = sext i32 0 to i64
  %t578 = call i32 @char-at(ptr %t576, i64 %t577)
  %t579 = icmp ne i32 %t578, 0
  store i1 %t579, ptr %and.val60, align 1
  br label %and.end60
and.end60:
  %t580 = load i1, ptr %and.val60, align 1
  br i1 %t580, label %cond.then59.0, label %cond.end59
cond.then59.0:
  %t581 = load ptr, ptr @g-entry-bufp, align 8
  %t582 = load ptr, ptr @g-def-stream, align 8
  %t583 = call i32 @fputs(ptr %t581, ptr %t582)
  br label %cond.end59
cond.end59:
  %t584 = load ptr, ptr @g-body-bufp, align 8
  %t585 = icmp ne ptr %t584, null
  store i1 %t585, ptr %and.val62, align 1
  br i1 %t585, label %and.rhs62, label %and.end62
and.rhs62:
  %t586 = load ptr, ptr @g-body-bufp, align 8
  %t587 = sext i32 0 to i64
  %t588 = call i32 @char-at(ptr %t586, i64 %t587)
  %t589 = icmp ne i32 %t588, 0
  store i1 %t589, ptr %and.val62, align 1
  br label %and.end62
and.end62:
  %t590 = load i1, ptr %and.val62, align 1
  br i1 %t590, label %cond.then61.0, label %cond.end61
cond.then61.0:
  %t591 = load ptr, ptr @g-body-bufp, align 8
  %t592 = load ptr, ptr @g-def-stream, align 8
  %t593 = call i32 @fputs(ptr %t591, ptr %t592)
  br label %cond.end61
cond.end61:
  %t594 = load ptr, ptr @g-def-stream, align 8
  %t595 = getelementptr inbounds [4 x i8], ptr @.str.801, i64 0, i64 0
  %t596 = call i32 (ptr, ptr, ...) @fprintf(ptr %t594, ptr %t595)
  %t597 = load ptr, ptr @g-entry-bufp, align 8
  call void @free(ptr %t597)
  %t598 = load ptr, ptr @g-body-bufp, align 8
  call void @free(ptr %t598)
  store ptr null, ptr @g-entry-bufp, align 8
  store ptr null, ptr @g-body-bufp, align 8
  %t599 = load i32, ptr @g-qq-used, align 4
  %t600 = icmp ne i32 %t599, 0
  br i1 %t600, label %cond.then63.0, label %cond.end63
cond.then63.0:
  %t601 = load ptr, ptr @g-decl-stream, align 8
  %t602 = load ptr, ptr @g-def-stream, align 8
  call void @emit-qq-helpers(ptr %t601, ptr %t602)
  br label %cond.end63
cond.end63:
  %t603 = load ptr, ptr %f.addr.0, align 8
  %t604 = getelementptr inbounds %Node, ptr %t603, i32 0, i32 1
  %t605 = load i32, ptr %t604, align 4
  call void @repl-jit-module(i32 %t605)
  store i32 0, ptr @g-qq-used, align 4
  %t607 = sext i32 0 to i64
  store i64 %t607, ptr %addr.addr.606, align 8
  %t609 = load ptr, ptr @g-jit, align 8
  %t610 = load ptr, ptr %eval-sym.addr.444, align 8
  %t611 = call ptr @LLVMOrcLLJITLookup(ptr %t609, ptr %addr.addr.606, ptr %t610)
  store ptr %t611, ptr %err.addr.608, align 8
  %t612 = load ptr, ptr %err.addr.608, align 8
  %t613 = icmp ne ptr %t612, null
  br i1 %t613, label %cond.then64.0, label %cond.end64
cond.then64.0:
  %t614 = load ptr, ptr @stderr, align 8
  %t615 = getelementptr inbounds [24 x i8], ptr @.str.802, i64 0, i64 0
  %t616 = load ptr, ptr %err.addr.608, align 8
  %t617 = call ptr @LLVMGetErrorMessage(ptr %t616)
  %t618 = call i32 (ptr, ptr, ...) @fprintf(ptr %t614, ptr %t615, ptr %t617)
  ret void
cond.end64:
  %t619 = load i64, ptr %addr.addr.606, align 8
  %t620 = sext i32 0 to i64
  %t621 = icmp ne i64 %t619, %t620
  br i1 %t621, label %cond.then65.0, label %cond.end65
cond.then65.0:
  %t622 = load i32, ptr %result-kind.addr.459, align 4
  %t623 = icmp eq i32 %t622, 4
  store i1 %t623, ptr %or.val67, align 1
  br i1 %t623, label %or.end67, label %or.rhs67
or.rhs67:
  %t624 = load i32, ptr %result-kind.addr.459, align 4
  %t625 = icmp eq i32 %t624, 1
  store i1 %t625, ptr %or.val68, align 1
  br i1 %t625, label %or.end68, label %or.rhs68
or.rhs68:
  %t626 = load i32, ptr %result-kind.addr.459, align 4
  %t627 = icmp eq i32 %t626, 2
  store i1 %t627, ptr %or.val69, align 1
  br i1 %t627, label %or.end69, label %or.rhs69
or.rhs69:
  %t628 = load i32, ptr %result-kind.addr.459, align 4
  %t629 = icmp eq i32 %t628, 3
  store i1 %t629, ptr %or.val69, align 1
  br label %or.end69
or.end69:
  %t630 = load i1, ptr %or.val69, align 1
  store i1 %t630, ptr %or.val68, align 1
  br label %or.end68
or.end68:
  %t631 = load i1, ptr %or.val68, align 1
  store i1 %t631, ptr %or.val67, align 1
  br label %or.end67
or.end67:
  %t632 = load i1, ptr %or.val67, align 1
  br i1 %t632, label %cond.then66.0, label %cond.test66.1
cond.then66.0:
  %t634 = load i64, ptr %addr.addr.606, align 8
  %t635 = inttoptr i64 %t634 to ptr
  store ptr %t635, ptr %fn.addr.633, align 8
  %t637 = load ptr, ptr %fn.addr.633, align 8
  %t638 = call i32 %t637()
  store i32 %t638, ptr %rv.addr.636, align 4
  %t639 = load ptr, ptr @stderr, align 8
  %t640 = getelementptr inbounds [6 x i8], ptr @.str.803, i64 0, i64 0
  %t641 = load i32, ptr %rv.addr.636, align 4
  %t642 = call i32 (ptr, ptr, ...) @fprintf(ptr %t639, ptr %t640, i32 %t641)
  br label %cond.end66
cond.test66.1:
  %t643 = load i32, ptr %result-kind.addr.459, align 4
  %t644 = icmp eq i32 %t643, 5
  br i1 %t644, label %cond.then66.1, label %cond.test66.2
cond.then66.1:
  %t646 = load i64, ptr %addr.addr.606, align 8
  %t647 = inttoptr i64 %t646 to ptr
  store ptr %t647, ptr %fn.addr.645, align 8
  %t649 = load ptr, ptr %fn.addr.645, align 8
  %t650 = call i64 %t649()
  store i64 %t650, ptr %rv.addr.648, align 8
  %t651 = load ptr, ptr @stderr, align 8
  %t652 = getelementptr inbounds [7 x i8], ptr @.str.804, i64 0, i64 0
  %t653 = load i64, ptr %rv.addr.648, align 8
  %t654 = call i32 (ptr, ptr, ...) @fprintf(ptr %t651, ptr %t652, i64 %t653)
  br label %cond.end66
cond.test66.2:
  %t655 = load i32, ptr %result-kind.addr.459, align 4
  %t656 = icmp eq i32 %t655, 10
  br i1 %t656, label %cond.then66.2, label %cond.test66.3
cond.then66.2:
  %t658 = load i64, ptr %addr.addr.606, align 8
  %t659 = inttoptr i64 %t658 to ptr
  store ptr %t659, ptr %fn.addr.657, align 8
  %t661 = load ptr, ptr %fn.addr.657, align 8
  %t662 = call ptr %t661()
  store ptr %t662, ptr %rv.addr.660, align 8
  %t663 = load ptr, ptr %rv.addr.660, align 8
  %t664 = icmp ne ptr %t663, null
  br i1 %t664, label %cond.then70.0, label %cond.test70.1
cond.then70.0:
  %t665 = load ptr, ptr @stderr, align 8
  %t666 = getelementptr inbounds [6 x i8], ptr @.str.805, i64 0, i64 0
  %t667 = load ptr, ptr %rv.addr.660, align 8
  %t668 = call i32 (ptr, ptr, ...) @fprintf(ptr %t665, ptr %t666, ptr %t667)
  br label %cond.end70
cond.test70.1:
  br i1 1, label %cond.then70.1, label %cond.end70
cond.then70.1:
  %t669 = load ptr, ptr @stderr, align 8
  %t670 = getelementptr inbounds [8 x i8], ptr @.str.806, i64 0, i64 0
  %t671 = call i32 (ptr, ptr, ...) @fprintf(ptr %t669, ptr %t670)
  br label %cond.end70
cond.end70:
  br label %cond.end66
cond.test66.3:
  %t672 = load i32, ptr %result-kind.addr.459, align 4
  %t673 = icmp eq i32 %t672, 0
  br i1 %t673, label %cond.then66.3, label %cond.test66.4
cond.then66.3:
  br label %cond.end66
cond.test66.4:
  br i1 1, label %cond.then66.4, label %cond.end66
cond.then66.4:
  br label %cond.end66
cond.end66:
  br label %cond.end65
cond.end65:
  br label %cond.end4
cond.end4:
  ret void
}

define void @repl-jit-module(i32 %line.arg) {
entry:
  %line.addr = alloca i32, align 4
  store i32 %line.arg, ptr %line.addr, align 4
  %ir-bufp.addr.12 = alloca ptr, align 8
  %ir-sizep.addr.13 = alloca i64, align 8
  %irs.addr.15 = alloca ptr, align 8
  %and.val1 = alloca i1, align 1
  %and.val3 = alloca i1, align 1
  %and.val5 = alloca i1, align 1
  %and.val7 = alloca i1, align 1
  %and.val9 = alloca i1, align 1
  %t0 = load ptr, ptr @g-type-stream, align 8
  %t1 = call i32 @fflush(ptr %t0)
  %t2 = load ptr, ptr @g-decl-stream, align 8
  %t3 = call i32 @fflush(ptr %t2)
  %t4 = load ptr, ptr @g-def-stream, align 8
  %t5 = call i32 @fflush(ptr %t4)
  %t6 = load ptr, ptr @g-type-stream, align 8
  %t7 = call i32 @fclose(ptr %t6)
  %t8 = load ptr, ptr @g-decl-stream, align 8
  %t9 = call i32 @fclose(ptr %t8)
  %t10 = load ptr, ptr @g-def-stream, align 8
  %t11 = call i32 @fclose(ptr %t10)
  store ptr null, ptr %ir-bufp.addr.12, align 8
  %t14 = sext i32 0 to i64
  store i64 %t14, ptr %ir-sizep.addr.13, align 8
  %t16 = call ptr @open_memstream(ptr %ir-bufp.addr.12, ptr %ir-sizep.addr.13)
  store ptr %t16, ptr %irs.addr.15, align 8
  %t17 = load ptr, ptr %irs.addr.15, align 8
  %t18 = getelementptr inbounds [23 x i8], ptr @.str.807, i64 0, i64 0
  %t19 = call i32 (ptr, ptr, ...) @fprintf(ptr %t17, ptr %t18)
  %t20 = load ptr, ptr %irs.addr.15, align 8
  %t21 = getelementptr inbounds [40 x i8], ptr @.str.808, i64 0, i64 0
  %t22 = call i32 (ptr, ptr, ...) @fprintf(ptr %t20, ptr %t21)
  %t23 = load ptr, ptr @g-repl-preamble, align 8
  %t24 = call i32 @fflush(ptr %t23)
  %t25 = load ptr, ptr @g-repl-preamble-bufp, align 8
  %t26 = icmp ne ptr %t25, null
  store i1 %t26, ptr %and.val1, align 1
  br i1 %t26, label %and.rhs1, label %and.end1
and.rhs1:
  %t27 = load ptr, ptr @g-repl-preamble-bufp, align 8
  %t28 = sext i32 0 to i64
  %t29 = call i32 @char-at(ptr %t27, i64 %t28)
  %t30 = icmp ne i32 %t29, 0
  store i1 %t30, ptr %and.val1, align 1
  br label %and.end1
and.end1:
  %t31 = load i1, ptr %and.val1, align 1
  br i1 %t31, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t32 = load ptr, ptr @g-repl-preamble-bufp, align 8
  %t33 = load ptr, ptr %irs.addr.15, align 8
  %t34 = call i32 @fputs(ptr %t32, ptr %t33)
  br label %cond.end0
cond.end0:
  %t35 = load ptr, ptr @g-type-bufp, align 8
  %t36 = icmp ne ptr %t35, null
  store i1 %t36, ptr %and.val3, align 1
  br i1 %t36, label %and.rhs3, label %and.end3
and.rhs3:
  %t37 = load ptr, ptr @g-type-bufp, align 8
  %t38 = sext i32 0 to i64
  %t39 = call i32 @char-at(ptr %t37, i64 %t38)
  %t40 = icmp ne i32 %t39, 0
  store i1 %t40, ptr %and.val3, align 1
  br label %and.end3
and.end3:
  %t41 = load i1, ptr %and.val3, align 1
  br i1 %t41, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t42 = load ptr, ptr @g-type-bufp, align 8
  %t43 = load ptr, ptr %irs.addr.15, align 8
  %t44 = call i32 @fputs(ptr %t42, ptr %t43)
  br label %cond.end2
cond.end2:
  %t45 = load ptr, ptr %irs.addr.15, align 8
  call void @emit-string-table(ptr %t45)
  %t46 = load ptr, ptr @g-decl-bufp, align 8
  %t47 = icmp ne ptr %t46, null
  store i1 %t47, ptr %and.val5, align 1
  br i1 %t47, label %and.rhs5, label %and.end5
and.rhs5:
  %t48 = load ptr, ptr @g-decl-bufp, align 8
  %t49 = sext i32 0 to i64
  %t50 = call i32 @char-at(ptr %t48, i64 %t49)
  %t51 = icmp ne i32 %t50, 0
  store i1 %t51, ptr %and.val5, align 1
  br label %and.end5
and.end5:
  %t52 = load i1, ptr %and.val5, align 1
  br i1 %t52, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t53 = load ptr, ptr @g-decl-bufp, align 8
  %t54 = load ptr, ptr %irs.addr.15, align 8
  %t55 = call i32 @fputs(ptr %t53, ptr %t54)
  br label %cond.end4
cond.end4:
  %t56 = load ptr, ptr @g-def-bufp, align 8
  %t57 = icmp ne ptr %t56, null
  store i1 %t57, ptr %and.val7, align 1
  br i1 %t57, label %and.rhs7, label %and.end7
and.rhs7:
  %t58 = load ptr, ptr @g-def-bufp, align 8
  %t59 = sext i32 0 to i64
  %t60 = call i32 @char-at(ptr %t58, i64 %t59)
  %t61 = icmp ne i32 %t60, 0
  store i1 %t61, ptr %and.val7, align 1
  br label %and.end7
and.end7:
  %t62 = load i1, ptr %and.val7, align 1
  br i1 %t62, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t63 = load ptr, ptr @g-def-bufp, align 8
  %t64 = load ptr, ptr %irs.addr.15, align 8
  %t65 = call i32 @fputs(ptr %t63, ptr %t64)
  br label %cond.end6
cond.end6:
  %t66 = load ptr, ptr %irs.addr.15, align 8
  %t67 = call i32 @fclose(ptr %t66)
  %t68 = load ptr, ptr %ir-bufp.addr.12, align 8
  %t69 = icmp ne ptr %t68, null
  store i1 %t69, ptr %and.val9, align 1
  br i1 %t69, label %and.rhs9, label %and.end9
and.rhs9:
  %t70 = load ptr, ptr %ir-bufp.addr.12, align 8
  %t71 = sext i32 0 to i64
  %t72 = call i32 @char-at(ptr %t70, i64 %t71)
  %t73 = icmp ne i32 %t72, 0
  store i1 %t73, ptr %and.val9, align 1
  br label %and.end9
and.end9:
  %t74 = load i1, ptr %and.val9, align 1
  br i1 %t74, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t75 = load ptr, ptr %ir-bufp.addr.12, align 8
  %t76 = load i32, ptr %line.addr, align 4
  call void @jit-add-module(ptr %t75, i32 %t76)
  br label %cond.end8
cond.end8:
  %t77 = load ptr, ptr @g-type-bufp, align 8
  call void @free(ptr %t77)
  %t78 = load ptr, ptr @g-decl-bufp, align 8
  call void @free(ptr %t78)
  %t79 = load ptr, ptr @g-def-bufp, align 8
  call void @free(ptr %t79)
  %t80 = load ptr, ptr %ir-bufp.addr.12, align 8
  call void @free(ptr %t80)
  ret void
}

define void @repl-include-all-libc() {
entry:
  %and.val1 = alloca i1, align 1
  call void @open-module-streams()
  %t0 = load ptr, ptr @g-decl-stream, align 8
  store ptr %t0, ptr @g-out, align 8
  %t1 = getelementptr inbounds [8 x i8], ptr @.str.809, i64 0, i64 0
  call void @emit-c-include(ptr %t1, i32 0)
  %t2 = getelementptr inbounds [9 x i8], ptr @.str.810, i64 0, i64 0
  call void @emit-c-include(ptr %t2, i32 0)
  %t3 = getelementptr inbounds [9 x i8], ptr @.str.811, i64 0, i64 0
  call void @emit-c-include(ptr %t3, i32 0)
  %t4 = getelementptr inbounds [8 x i8], ptr @.str.812, i64 0, i64 0
  call void @emit-c-include(ptr %t4, i32 0)
  %t5 = getelementptr inbounds [9 x i8], ptr @.str.813, i64 0, i64 0
  call void @emit-c-include(ptr %t5, i32 0)
  %t6 = load ptr, ptr @g-type-stream, align 8
  %t7 = call i32 @fclose(ptr %t6)
  %t8 = load ptr, ptr @g-decl-stream, align 8
  %t9 = call i32 @fclose(ptr %t8)
  %t10 = load ptr, ptr @g-def-stream, align 8
  %t11 = call i32 @fclose(ptr %t10)
  %t12 = load ptr, ptr @g-decl-bufp, align 8
  %t13 = icmp ne ptr %t12, null
  store i1 %t13, ptr %and.val1, align 1
  br i1 %t13, label %and.rhs1, label %and.end1
and.rhs1:
  %t14 = load ptr, ptr @g-decl-bufp, align 8
  %t15 = sext i32 0 to i64
  %t16 = call i32 @char-at(ptr %t14, i64 %t15)
  %t17 = icmp ne i32 %t16, 0
  store i1 %t17, ptr %and.val1, align 1
  br label %and.end1
and.end1:
  %t18 = load i1, ptr %and.val1, align 1
  br i1 %t18, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t19 = load ptr, ptr @g-decl-bufp, align 8
  %t20 = load ptr, ptr @g-repl-preamble, align 8
  %t21 = call i32 @fputs(ptr %t19, ptr %t20)
  br label %cond.end0
cond.end0:
  %t22 = load ptr, ptr @g-type-bufp, align 8
  call void @free(ptr %t22)
  %t23 = load ptr, ptr @g-decl-bufp, align 8
  call void @free(ptr %t23)
  %t24 = load ptr, ptr @g-def-bufp, align 8
  call void @free(ptr %t24)
  %t25 = load ptr, ptr @g-repl-preamble, align 8
  %t26 = getelementptr inbounds [2 x i8], ptr @.str.814, i64 0, i64 0
  %t27 = call i32 (ptr, ptr, ...) @fprintf(ptr %t25, ptr %t26)
  ret void
}

define void @repl-register-node() {
entry:
  %sd.addr.0 = alloca ptr, align 8
  %sym.addr.92 = alloca ptr, align 8
  %sym.addr.102 = alloca ptr, align 8
  %sym.addr.112 = alloca ptr, align 8
  %sym.addr.122 = alloca ptr, align 8
  %t1 = getelementptr inbounds [5 x i8], ptr @.str.815, i64 0, i64 0
  %t2 = call ptr @register-struct(ptr %t1)
  store ptr %t2, ptr %sd.addr.0, align 8
  %t3 = load ptr, ptr %sd.addr.0, align 8
  %t4 = getelementptr inbounds %StructDef, ptr %t3, i32 0, i32 3
  store i32 6, ptr %t4, align 4
  %t5 = load ptr, ptr %sd.addr.0, align 8
  %t6 = sext i32 6 to i64
  %t7 = sext i32 8 to i64
  %t8 = mul nsw i64 %t6, %t7
  %t9 = call ptr @arena-alloc(i64 %t8)
  %t10 = getelementptr inbounds %StructDef, ptr %t5, i32 0, i32 1
  store ptr %t9, ptr %t10, align 8
  %t11 = load ptr, ptr %sd.addr.0, align 8
  %t12 = sext i32 6 to i64
  %t13 = sext i32 8 to i64
  %t14 = mul nsw i64 %t12, %t13
  %t15 = call ptr @arena-alloc(i64 %t14)
  %t16 = getelementptr inbounds %StructDef, ptr %t11, i32 0, i32 2
  store ptr %t15, ptr %t16, align 8
  %t17 = load ptr, ptr %sd.addr.0, align 8
  %t18 = getelementptr inbounds %StructDef, ptr %t17, i32 0, i32 1
  %t19 = load ptr, ptr %t18, align 8
  %t20 = sext i32 0 to i64
  %t21 = getelementptr inbounds [5 x i8], ptr @.str.816, i64 0, i64 0
  %t22 = getelementptr inbounds ptr, ptr %t19, i64 %t20
  store ptr %t21, ptr %t22, align 8
  %t23 = load ptr, ptr %sd.addr.0, align 8
  %t24 = getelementptr inbounds %StructDef, ptr %t23, i32 0, i32 1
  %t25 = load ptr, ptr %t24, align 8
  %t26 = sext i32 1 to i64
  %t27 = getelementptr inbounds [5 x i8], ptr @.str.817, i64 0, i64 0
  %t28 = getelementptr inbounds ptr, ptr %t25, i64 %t26
  store ptr %t27, ptr %t28, align 8
  %t29 = load ptr, ptr %sd.addr.0, align 8
  %t30 = getelementptr inbounds %StructDef, ptr %t29, i32 0, i32 1
  %t31 = load ptr, ptr %t30, align 8
  %t32 = sext i32 2 to i64
  %t33 = getelementptr inbounds [2 x i8], ptr @.str.818, i64 0, i64 0
  %t34 = getelementptr inbounds ptr, ptr %t31, i64 %t32
  store ptr %t33, ptr %t34, align 8
  %t35 = load ptr, ptr %sd.addr.0, align 8
  %t36 = getelementptr inbounds %StructDef, ptr %t35, i32 0, i32 1
  %t37 = load ptr, ptr %t36, align 8
  %t38 = sext i32 3 to i64
  %t39 = getelementptr inbounds [2 x i8], ptr @.str.819, i64 0, i64 0
  %t40 = getelementptr inbounds ptr, ptr %t37, i64 %t38
  store ptr %t39, ptr %t40, align 8
  %t41 = load ptr, ptr %sd.addr.0, align 8
  %t42 = getelementptr inbounds %StructDef, ptr %t41, i32 0, i32 1
  %t43 = load ptr, ptr %t42, align 8
  %t44 = sext i32 4 to i64
  %t45 = getelementptr inbounds [4 x i8], ptr @.str.820, i64 0, i64 0
  %t46 = getelementptr inbounds ptr, ptr %t43, i64 %t44
  store ptr %t45, ptr %t46, align 8
  %t47 = load ptr, ptr %sd.addr.0, align 8
  %t48 = getelementptr inbounds %StructDef, ptr %t47, i32 0, i32 1
  %t49 = load ptr, ptr %t48, align 8
  %t50 = sext i32 5 to i64
  %t51 = getelementptr inbounds [4 x i8], ptr @.str.821, i64 0, i64 0
  %t52 = getelementptr inbounds ptr, ptr %t49, i64 %t50
  store ptr %t51, ptr %t52, align 8
  %t53 = load ptr, ptr %sd.addr.0, align 8
  %t54 = getelementptr inbounds %StructDef, ptr %t53, i32 0, i32 2
  %t55 = load ptr, ptr %t54, align 8
  %t56 = sext i32 0 to i64
  %t57 = load ptr, ptr @ty-i32, align 8
  %t58 = getelementptr inbounds ptr, ptr %t55, i64 %t56
  store ptr %t57, ptr %t58, align 8
  %t59 = load ptr, ptr %sd.addr.0, align 8
  %t60 = getelementptr inbounds %StructDef, ptr %t59, i32 0, i32 2
  %t61 = load ptr, ptr %t60, align 8
  %t62 = sext i32 1 to i64
  %t63 = load ptr, ptr @ty-i32, align 8
  %t64 = getelementptr inbounds ptr, ptr %t61, i64 %t62
  store ptr %t63, ptr %t64, align 8
  %t65 = load ptr, ptr %sd.addr.0, align 8
  %t66 = getelementptr inbounds %StructDef, ptr %t65, i32 0, i32 2
  %t67 = load ptr, ptr %t66, align 8
  %t68 = sext i32 2 to i64
  %t69 = load ptr, ptr @ty-i64, align 8
  %t70 = getelementptr inbounds ptr, ptr %t67, i64 %t68
  store ptr %t69, ptr %t70, align 8
  %t71 = load ptr, ptr %sd.addr.0, align 8
  %t72 = getelementptr inbounds %StructDef, ptr %t71, i32 0, i32 2
  %t73 = load ptr, ptr %t72, align 8
  %t74 = sext i32 3 to i64
  %t75 = load ptr, ptr @ty-ptr, align 8
  %t76 = getelementptr inbounds ptr, ptr %t73, i64 %t74
  store ptr %t75, ptr %t76, align 8
  %t77 = load ptr, ptr %sd.addr.0, align 8
  %t78 = getelementptr inbounds %StructDef, ptr %t77, i32 0, i32 2
  %t79 = load ptr, ptr %t78, align 8
  %t80 = sext i32 4 to i64
  %t81 = load ptr, ptr @ty-ptr, align 8
  %t82 = getelementptr inbounds ptr, ptr %t79, i64 %t80
  store ptr %t81, ptr %t82, align 8
  %t83 = load ptr, ptr %sd.addr.0, align 8
  %t84 = getelementptr inbounds %StructDef, ptr %t83, i32 0, i32 2
  %t85 = load ptr, ptr %t84, align 8
  %t86 = sext i32 5 to i64
  %t87 = load ptr, ptr @ty-ptr, align 8
  %t88 = getelementptr inbounds ptr, ptr %t85, i64 %t86
  store ptr %t87, ptr %t88, align 8
  %t89 = load ptr, ptr @g-repl-preamble, align 8
  %t90 = getelementptr inbounds [49 x i8], ptr @.str.822, i64 0, i64 0
  %t91 = call i32 (ptr, ptr, ...) @fprintf(ptr %t89, ptr %t90)
  %t93 = load ptr, ptr @g-globals, align 8
  %t94 = getelementptr inbounds [9 x i8], ptr @.str.823, i64 0, i64 0
  %t95 = load ptr, ptr @ty-i32, align 8
  %t96 = call ptr @scope-define(ptr %t93, ptr %t94, ptr %t95, ptr null, i32 0)
  store ptr %t96, ptr %sym.addr.92, align 8
  %t97 = load ptr, ptr %sym.addr.92, align 8
  %t98 = getelementptr inbounds %Sym, ptr %t97, i32 0, i32 4
  store i32 1, ptr %t98, align 4
  %t99 = load ptr, ptr %sym.addr.92, align 8
  %t100 = getelementptr inbounds [2 x i8], ptr @.str.824, i64 0, i64 0
  %t101 = getelementptr inbounds %Sym, ptr %t99, i32 0, i32 5
  store ptr %t100, ptr %t101, align 8
  %t103 = load ptr, ptr @g-globals, align 8
  %t104 = getelementptr inbounds [9 x i8], ptr @.str.825, i64 0, i64 0
  %t105 = load ptr, ptr @ty-i32, align 8
  %t106 = call ptr @scope-define(ptr %t103, ptr %t104, ptr %t105, ptr null, i32 0)
  store ptr %t106, ptr %sym.addr.102, align 8
  %t107 = load ptr, ptr %sym.addr.102, align 8
  %t108 = getelementptr inbounds %Sym, ptr %t107, i32 0, i32 4
  store i32 1, ptr %t108, align 4
  %t109 = load ptr, ptr %sym.addr.102, align 8
  %t110 = getelementptr inbounds [2 x i8], ptr @.str.826, i64 0, i64 0
  %t111 = getelementptr inbounds %Sym, ptr %t109, i32 0, i32 5
  store ptr %t110, ptr %t111, align 8
  %t113 = load ptr, ptr @g-globals, align 8
  %t114 = getelementptr inbounds [9 x i8], ptr @.str.827, i64 0, i64 0
  %t115 = load ptr, ptr @ty-i32, align 8
  %t116 = call ptr @scope-define(ptr %t113, ptr %t114, ptr %t115, ptr null, i32 0)
  store ptr %t116, ptr %sym.addr.112, align 8
  %t117 = load ptr, ptr %sym.addr.112, align 8
  %t118 = getelementptr inbounds %Sym, ptr %t117, i32 0, i32 4
  store i32 1, ptr %t118, align 4
  %t119 = load ptr, ptr %sym.addr.112, align 8
  %t120 = getelementptr inbounds [2 x i8], ptr @.str.828, i64 0, i64 0
  %t121 = getelementptr inbounds %Sym, ptr %t119, i32 0, i32 5
  store ptr %t120, ptr %t121, align 8
  %t123 = load ptr, ptr @g-globals, align 8
  %t124 = getelementptr inbounds [10 x i8], ptr @.str.829, i64 0, i64 0
  %t125 = load ptr, ptr @ty-i32, align 8
  %t126 = call ptr @scope-define(ptr %t123, ptr %t124, ptr %t125, ptr null, i32 0)
  store ptr %t126, ptr %sym.addr.122, align 8
  %t127 = load ptr, ptr %sym.addr.122, align 8
  %t128 = getelementptr inbounds %Sym, ptr %t127, i32 0, i32 4
  store i32 1, ptr %t128, align 4
  %t129 = load ptr, ptr %sym.addr.122, align 8
  %t130 = getelementptr inbounds [2 x i8], ptr @.str.830, i64 0, i64 0
  %t131 = getelementptr inbounds %Sym, ptr %t129, i32 0, i32 5
  store ptr %t130, ptr %t131, align 8
  ret void
}

define void @repl-main() {
entry:
  %running.addr.5 = alloca i32, align 4
  %input.addr.8 = alloca ptr, align 8
  %forms.addr.21 = alloca ptr, align 8
  %fc.addr.24 = alloca ptr, align 8
  %f.addr.28 = alloca ptr, align 8
  %t0 = load ptr, ptr @stderr, align 8
  %t1 = getelementptr inbounds [36 x i8], ptr @.str.831, i64 0, i64 0
  %t2 = call i32 (ptr, ptr, ...) @fprintf(ptr %t0, ptr %t1)
  %t3 = getelementptr inbounds [7 x i8], ptr @.str.832, i64 0, i64 0
  store ptr %t3, ptr @g-source-path, align 8
  call void @compiler-init()
  %t4 = call ptr @open_memstream(ptr @g-repl-preamble-bufp, ptr @g-repl-preamble-sizep)
  store ptr %t4, ptr @g-repl-preamble, align 8
  call void @repl-include-all-libc()
  call void @repl-register-node()
  store i32 1, ptr %running.addr.5, align 4
  br label %while.cond0
while.cond0:
  %t6 = load i32, ptr %running.addr.5, align 4
  %t7 = icmp ne i32 %t6, 0
  br i1 %t7, label %while.body0, label %while.end0
while.body0:
  %t9 = call ptr @repl-read-input()
  store ptr %t9, ptr %input.addr.8, align 8
  %t10 = load ptr, ptr %input.addr.8, align 8
  %t11 = icmp eq ptr %t10, null
  br i1 %t11, label %cond.then1.0, label %cond.end1
cond.then1.0:
  %t12 = load ptr, ptr @stderr, align 8
  %t13 = getelementptr inbounds [2 x i8], ptr @.str.833, i64 0, i64 0
  %t14 = call i32 (ptr, ptr, ...) @fprintf(ptr %t12, ptr %t13)
  store i32 0, ptr %running.addr.5, align 4
  br label %cond.end1
cond.end1:
  %t15 = load ptr, ptr %input.addr.8, align 8
  %t16 = icmp ne ptr %t15, null
  br i1 %t16, label %cond.then2.0, label %cond.end2
cond.then2.0:
  %t17 = load i32, ptr %running.addr.5, align 4
  %t18 = icmp ne i32 %t17, 0
  br i1 %t18, label %cond.then3.0, label %cond.end3
cond.then3.0:
  %t19 = load ptr, ptr %input.addr.8, align 8
  store ptr %t19, ptr @g-src, align 8
  %t20 = sext i32 0 to i64
  store i64 %t20, ptr @g-pos, align 8
  store i32 1, ptr @g-line, align 4
  store i32 0, ptr @g-peek-valid, align 4
  %t22 = call ptr @read-program()
  %t23 = call ptr @desugar(ptr %t22)
  store ptr %t23, ptr %forms.addr.21, align 8
  %t25 = load ptr, ptr %forms.addr.21, align 8
  store ptr %t25, ptr %fc.addr.24, align 8
  br label %while.cond4
while.cond4:
  %t26 = load ptr, ptr %fc.addr.24, align 8
  %t27 = icmp ne ptr %t26, null
  br i1 %t27, label %while.body4, label %while.end4
while.body4:
  %t29 = load ptr, ptr %fc.addr.24, align 8
  %t30 = getelementptr inbounds %Node, ptr %t29, i32 0, i32 4
  %t31 = load ptr, ptr %t30, align 8
  store ptr %t31, ptr %f.addr.28, align 8
  %t32 = call i32 @repl_try()
  %t33 = icmp ne i32 %t32, 0
  br i1 %t33, label %cond.then5.0, label %cond.end5
cond.then5.0:
  %t34 = load ptr, ptr @stderr, align 8
  %t35 = getelementptr inbounds [21 x i8], ptr @.str.834, i64 0, i64 0
  %t36 = call i32 (ptr, ptr, ...) @fprintf(ptr %t34, ptr %t35)
  br label %cond.end5
cond.end5:
  %t37 = call i32 @repl_try()
  %t38 = icmp eq i32 %t37, 0
  br i1 %t38, label %cond.then6.0, label %cond.end6
cond.then6.0:
  %t39 = load ptr, ptr %f.addr.28, align 8
  call void @repl-eval-form(ptr %t39)
  br label %cond.end6
cond.end6:
  %t40 = load ptr, ptr %fc.addr.24, align 8
  %t41 = getelementptr inbounds %Node, ptr %t40, i32 0, i32 5
  %t42 = load ptr, ptr %t41, align 8
  store ptr %t42, ptr %fc.addr.24, align 8
  br label %while.cond4
while.end4:
  %t43 = load ptr, ptr %input.addr.8, align 8
  call void @free(ptr %t43)
  br label %cond.end3
cond.end3:
  br label %cond.end2
cond.end2:
  br label %while.cond0
while.end0:
  ret void
}

define void @add-include-path(ptr %path.arg) {
entry:
  %path.addr = alloca ptr, align 8
  store ptr %path.arg, ptr %path.addr, align 8
  %t0 = load ptr, ptr @g-include-paths, align 8
  %t1 = icmp eq ptr %t0, null
  br i1 %t1, label %cond.then0.0, label %cond.end0
cond.then0.0:
  %t2 = sext i32 64 to i64
  %t3 = sext i32 8 to i64
  %t4 = mul nsw i64 %t2, %t3
  %t5 = call ptr @malloc(i64 %t4)
  store ptr %t5, ptr @g-include-paths, align 8
  br label %cond.end0
cond.end0:
  %t6 = load ptr, ptr @g-include-paths, align 8
  %t7 = load i32, ptr @g-num-include-paths, align 4
  %t8 = sext i32 %t7 to i64
  %t9 = load ptr, ptr %path.addr, align 8
  %t10 = getelementptr inbounds ptr, ptr %t6, i64 %t8
  store ptr %t9, ptr %t10, align 8
  %t11 = load i32, ptr @g-num-include-paths, align 4
  %t12 = add nsw i32 %t11, 1
  store i32 %t12, ptr @g-num-include-paths, align 4
  ret void
}

define i32 @main(i32 %argc.arg, ptr %argv.arg) {
entry:
  %argc.addr = alloca i32, align 4
  store i32 %argc.arg, ptr %argc.addr, align 4
  %argv.addr = alloca ptr, align 8
  store ptr %argv.arg, ptr %argv.addr, align 8
  %source-file.addr.0 = alloca ptr, align 8
  %i.addr.1 = alloca i32, align 4
  %arg.addr.5 = alloca ptr, align 8
  %or.val2 = alloca i1, align 1
  %src.addr.78 = alloca ptr, align 8
  %forms.addr.83 = alloca ptr, align 8
  store ptr null, ptr %source-file.addr.0, align 8
  store i32 1, ptr %i.addr.1, align 4
  br label %while.cond0
while.cond0:
  %t2 = load i32, ptr %i.addr.1, align 4
  %t3 = load i32, ptr %argc.addr, align 4
  %t4 = icmp slt i32 %t2, %t3
  br i1 %t4, label %while.body0, label %while.end0
while.body0:
  %t6 = load ptr, ptr %argv.addr, align 8
  %t7 = load i32, ptr %i.addr.1, align 4
  %t8 = sext i32 %t7 to i64
  %t9 = getelementptr inbounds ptr, ptr %t6, i64 %t8
  %t10 = load ptr, ptr %t9, align 8
  store ptr %t10, ptr %arg.addr.5, align 8
  %t11 = load ptr, ptr %arg.addr.5, align 8
  %t12 = getelementptr inbounds [12 x i8], ptr @.str.835, i64 0, i64 0
  %t13 = call i32 @strcmp(ptr %t11, ptr %t12)
  %t14 = icmp eq i32 %t13, 0
  br i1 %t14, label %cond.then1.0, label %cond.test1.1
cond.then1.0:
  store i32 1, ptr @g-emit-nuch, align 4
  br label %cond.end1
cond.test1.1:
  %t15 = load ptr, ptr %arg.addr.5, align 8
  %t16 = getelementptr inbounds [15 x i8], ptr @.str.836, i64 0, i64 0
  %t17 = call i32 @strcmp(ptr %t15, ptr %t16)
  %t18 = icmp eq i32 %t17, 0
  br i1 %t18, label %cond.then1.1, label %cond.test1.2
cond.then1.1:
  store i32 1, ptr @g-emit-cheader, align 4
  br label %cond.end1
cond.test1.2:
  %t19 = load ptr, ptr %arg.addr.5, align 8
  %t20 = getelementptr inbounds [3 x i8], ptr @.str.837, i64 0, i64 0
  %t21 = call i32 @strcmp(ptr %t19, ptr %t20)
  %t22 = icmp eq i32 %t21, 0
  store i1 %t22, ptr %or.val2, align 1
  br i1 %t22, label %or.end2, label %or.rhs2
or.rhs2:
  %t23 = load ptr, ptr %arg.addr.5, align 8
  %t24 = getelementptr inbounds [14 x i8], ptr @.str.838, i64 0, i64 0
  %t25 = call i32 @strcmp(ptr %t23, ptr %t24)
  %t26 = icmp eq i32 %t25, 0
  store i1 %t26, ptr %or.val2, align 1
  br label %or.end2
or.end2:
  %t27 = load i1, ptr %or.val2, align 1
  br i1 %t27, label %cond.then1.2, label %cond.test1.3
cond.then1.2:
  store i32 1, ptr @g-interactive, align 4
  br label %cond.end1
cond.test1.3:
  %t28 = load ptr, ptr %arg.addr.5, align 8
  %t29 = getelementptr inbounds [3 x i8], ptr @.str.839, i64 0, i64 0
  %t30 = sext i32 2 to i64
  %t31 = call i32 @strncmp(ptr %t28, ptr %t29, i64 %t30)
  %t32 = icmp eq i32 %t31, 0
  br i1 %t32, label %cond.then1.3, label %cond.test1.4
cond.then1.3:
  %t33 = load ptr, ptr %arg.addr.5, align 8
  %t34 = call i64 @strlen(ptr %t33)
  %t35 = sext i32 2 to i64
  %t36 = icmp sgt i64 %t34, %t35
  br i1 %t36, label %cond.then3.0, label %cond.test3.1
cond.then3.0:
  %t37 = load ptr, ptr %arg.addr.5, align 8
  %t38 = sext i32 2 to i64
  %t39 = getelementptr inbounds i8, ptr %t37, i64 %t38
  call void @add-include-path(ptr %t39)
  br label %cond.end3
cond.test3.1:
  br i1 1, label %cond.then3.1, label %cond.end3
cond.then3.1:
  %t40 = load i32, ptr %i.addr.1, align 4
  %t41 = add nsw i32 %t40, 1
  store i32 %t41, ptr %i.addr.1, align 4
  %t42 = load i32, ptr %i.addr.1, align 4
  %t43 = load i32, ptr %argc.addr, align 4
  %t44 = icmp sge i32 %t42, %t43
  br i1 %t44, label %cond.then4.0, label %cond.end4
cond.then4.0:
  %t45 = load ptr, ptr @stderr, align 8
  %t46 = getelementptr inbounds [25 x i8], ptr @.str.840, i64 0, i64 0
  %t47 = call i32 (ptr, ptr, ...) @fprintf(ptr %t45, ptr %t46)
  ret i32 2
cond.end4:
  %t48 = load ptr, ptr %argv.addr, align 8
  %t49 = load i32, ptr %i.addr.1, align 4
  %t50 = sext i32 %t49 to i64
  %t51 = getelementptr inbounds ptr, ptr %t48, i64 %t50
  %t52 = load ptr, ptr %t51, align 8
  call void @add-include-path(ptr %t52)
  br label %cond.end3
cond.end3:
  br label %cond.end1
cond.test1.4:
  %t53 = load ptr, ptr %arg.addr.5, align 8
  %t54 = sext i32 0 to i64
  %t55 = call i32 @char-at(ptr %t53, i64 %t54)
  %t56 = icmp eq i32 %t55, 45
  br i1 %t56, label %cond.then1.4, label %cond.test1.5
cond.then1.4:
  %t57 = load ptr, ptr @stderr, align 8
  %t58 = getelementptr inbounds [18 x i8], ptr @.str.841, i64 0, i64 0
  %t59 = load ptr, ptr %arg.addr.5, align 8
  %t60 = call i32 (ptr, ptr, ...) @fprintf(ptr %t57, ptr %t58, ptr %t59)
  ret i32 2
cond.test1.5:
  br i1 1, label %cond.then1.5, label %cond.end1
cond.then1.5:
  %t61 = load ptr, ptr %source-file.addr.0, align 8
  %t62 = icmp eq ptr %t61, null
  br i1 %t62, label %cond.then5.0, label %cond.test5.1
cond.then5.0:
  %t63 = load ptr, ptr %arg.addr.5, align 8
  store ptr %t63, ptr %source-file.addr.0, align 8
  br label %cond.end5
cond.test5.1:
  br i1 1, label %cond.then5.1, label %cond.end5
cond.then5.1:
  %t64 = load ptr, ptr @stderr, align 8
  %t65 = getelementptr inbounds [25 x i8], ptr @.str.842, i64 0, i64 0
  %t66 = load ptr, ptr %arg.addr.5, align 8
  %t67 = call i32 (ptr, ptr, ...) @fprintf(ptr %t64, ptr %t65, ptr %t66)
  ret i32 2
cond.end5:
  br label %cond.end1
cond.end1:
  %t68 = load i32, ptr %i.addr.1, align 4
  %t69 = add nsw i32 %t68, 1
  store i32 %t69, ptr %i.addr.1, align 4
  br label %while.cond0
while.end0:
  %t70 = load i32, ptr @g-interactive, align 4
  %t71 = icmp ne i32 %t70, 0
  br i1 %t71, label %cond.then6.0, label %cond.end6
cond.then6.0:
  call void @repl-main()
  ret i32 0
cond.end6:
  %t72 = load ptr, ptr %source-file.addr.0, align 8
  %t73 = icmp eq ptr %t72, null
  br i1 %t73, label %cond.then7.0, label %cond.end7
cond.then7.0:
  %t74 = load ptr, ptr @stderr, align 8
  %t75 = getelementptr inbounds [75 x i8], ptr @.str.843, i64 0, i64 0
  %t76 = call i32 (ptr, ptr, ...) @fprintf(ptr %t74, ptr %t75)
  ret i32 2
cond.end7:
  %t77 = load ptr, ptr %source-file.addr.0, align 8
  store ptr %t77, ptr @g-source-path, align 8
  %t79 = load ptr, ptr %source-file.addr.0, align 8
  %t80 = call ptr @read-file(ptr %t79)
  store ptr %t80, ptr %src.addr.78, align 8
  call void @compiler-init()
  %t81 = load ptr, ptr %src.addr.78, align 8
  store ptr %t81, ptr @g-src, align 8
  %t82 = sext i32 0 to i64
  store i64 %t82, ptr @g-pos, align 8
  store i32 1, ptr @g-line, align 4
  %t84 = call ptr @read-program()
  %t85 = call ptr @desugar(ptr %t84)
  store ptr %t85, ptr %forms.addr.83, align 8
  %t86 = load i32, ptr @g-emit-nuch, align 4
  %t87 = icmp ne i32 %t86, 0
  br i1 %t87, label %cond.then8.0, label %cond.end8
cond.then8.0:
  %t88 = load ptr, ptr %forms.addr.83, align 8
  %t89 = load ptr, ptr %source-file.addr.0, align 8
  call void @emit-nuch-header(ptr %t88, ptr %t89)
  ret i32 0
cond.end8:
  %t90 = load i32, ptr @g-emit-cheader, align 4
  %t91 = icmp ne i32 %t90, 0
  br i1 %t91, label %cond.then9.0, label %cond.end9
cond.then9.0:
  %t92 = load ptr, ptr %forms.addr.83, align 8
  %t93 = load ptr, ptr %source-file.addr.0, align 8
  call void @emit-cheader-header(ptr %t92, ptr %t93)
  ret i32 0
cond.end9:
  call void @open-module-streams()
  %t94 = load ptr, ptr %forms.addr.83, align 8
  call void @emit-toplevel-forms(ptr %t94)
  %t95 = load ptr, ptr %source-file.addr.0, align 8
  call void @flush-module-ir(ptr %t95)
  ret i32 0
}

