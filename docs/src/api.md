```@meta
CurrentModule = Liquid
```

# API reference

```@docs
Liquid
```

## Rendering

```@docs
render
parse_template
get_template
Template
```

## Configuration

```@docs
Environment
default_environment
to_globals
```

## Loaders

```@docs
AbstractLoader
NullLoader
FileSystemLoader
get_source
```

## Exposing your own types

```@docs
liquid_properties
liquid_get
@liquid_drop
```

## Errors

```@docs
LiquidError
LiquidSyntaxError
LiquidArgumentError
LiquidUndefinedError
```

## Value model

The rules that make rendering lenient. These are the functions to add methods to
when your own type should behave a particular way in a template.

```@docs
is_truthy
to_liquid_string
to_number
is_blank
is_empty
liquid_equal
liquid_less
liquid_contains
compare
IncomparableValues
EMPTY
BLANK
Empty
Blank
```

## Extension points

### Tags

```@docs
TagDef
register_tag!
default_tags
Parser
parse_block!
syntax_error
parse_nodes
peek
advance!
```

### Filters

```@docs
register_filter!
default_filters
needs_context
filter_error
FilterError
apply_filter
```

### Nodes and rendering

```@docs
Node
render_node
render_nodes
render_block
is_blank_node
Context
evaluate
to_iterable
escape_html
```

## Stages

The three stages are usable on their own.

### Lexer

```@docs
tokenize
apply_whitespace_control
Token
TokenKind
tag_args
```

### Expressions

```@docs
tokenize_expression
ExprToken
ExprTokenKind
Expression
LiteralExpr
VariableExpr
RangeExpr
CompareExpr
CompareOp
BooleanExpr
NotExpr
FilterCall
FilteredExpr
parse_value
parse_condition
parse_filtered
```

### AST

```@docs
TextNode
OutputNode
IfNode
ConditionalBranch
CaseNode
CaseBranch
ForNode
loop_name
BreakNode
ContinueNode
AssignNode
CaptureNode
EchoNode
CycleNode
IncrementNode
DecrementNode
```

## Index

```@index
```
