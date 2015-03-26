# vi wrapper.

    accepts output from grep -n so     "v  file:123"        ->   "vi +123 file"
    also accepts package names like    "v  Foo::Bar::Baz"   ->   "vi Foo/Bar/Baz.pm"
    also accepts package->method like  "v 'Foo::Bar->baz'"  ->   "vi Foo/Bar.pm +/sub\s\+baz\>"
    also accepts output from perl -c   "v  Foo.pm line 12." ->   "vi +12 Foo.pm"
    also searches @INC and $ENV{OPENSRS_HOME}/lib and $ENV{CONTROL_PANEL_HOME}/lib

