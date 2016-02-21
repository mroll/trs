source rewriter.tcl


set terms {}
lappend terms "(7 * x) + (8 * x)"
lappend terms "(7 * x) - (8 * x)"
lappend terms "y / y"
lappend terms "h * h**4"
lappend terms "g**2 * g**3"
lappend terms "i * i"
lappend terms "15 * (7 - x)"
lappend terms "diff(10, x)"
lappend terms "diff(sin(y), y)"
lappend terms "diff(cos(h), h)"
lappend terms "diff(y**10, y)"
lappend terms "diff(8 + x, p)"
lappend terms "diff((9 - x) + (22 * x), y)"
lappend terms "diff(r, r)"
lappend terms "diff((9 - x) * (22 * x), y)"
lappend terms "diff(7*x, x)"
lappend terms "diff(6 * z**5, z)"
lappend terms "diff(x, y)"
lappend terms "diff(9 - x, y)"
lappend terms "diff(22 * x, y)"
lappend terms "diff(7 - y, y)"
lappend terms "0 + (10 - 7 + x -y)"

foreach t $terms {
    puts [format "%-30s ---> %-30s" $t [eval-exp [trs::simplify [parse $t] $::rules]]]
}
