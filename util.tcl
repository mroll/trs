proc wsplit {str sep} {
  split [string map [list $sep \0] $str] \0
} ;# RS

proc first { list } { lindex $list 0 }

proc forindex { i list body } {
    set len [llength $list]
    set script [subst { for {set $i 0} {$$i < $len} {incr $i} { $body } }]

    uplevel $script
}

# inefficient union, I know, but it has to maintain ordering
proc union { a b } {
    set u {}
    foreach el [concat $a $b] {
        if { [lsearch $u $el] == -1 } { lappend u $el }
    }

    set u
}

proc newvar { v i } { join [list $v $i] _ }
