#!/usr/bin/perl -w

# vi wrapper.
# accepts output from grep -n so     "v  file:123"        ->   "vi +123 file"
# also accepts package names like    "v  Foo::Bar::Baz"   ->   "vi Foo/Bar/Baz.pm"
# also accepts package->method like  "v 'Foo::Bar->baz'"  ->   "vi Foo/Bar.pm +/sub\s\+baz\>"
# also accepts output from perl -c   "v  Foo.pm line 12." ->   "vi +12 Foo.pm"
# also searches @INC and $ENV{OPENSRS_HOME}/lib and $ENV{CONTROL_PANEL_HOME}/lib

use strict;

sub parse_args {
    if ( not @ARGV ) {
        print "usage: $0 filename:123                 # from grep -n\n";
        print "usage: $0 path::filename:123           # from stack trace\n";
        print "usage: $0 path::module_no_dot_pm:123   # from stack trace alt\n";
        print "usage: $0 file:/path/filename,line:123 # from stack trace alt\n";
        print "usage: $0 'path::filename->method'     # from code\n";
        print "usage: $0  path::filename::method      # from code\n";
        exit 1;
    }

    # I often type "v" then switch to anther tab,
    # then come back and type "v file"
    # So I end up with "v v file".
    # So this removes redundant leading v | vi | vim | vil | vic
    if ( @ARGV > 1 && $ARGV[0] =~ /^v(?:i[clm]?)?$/ ) {
        my $orig_first_arg = $ARGV[0];
        do {
            shift @ARGV;
        } while ( @ARGV && $ARGV[0] =~ /^v(?:i[clm]?)?$/ );
        if ( not @ARGV ) {
            unshift @ARGV, $orig_first_arg;
        }
    }

    my (@vi_args, $found_at_least_one_file);

WHILE_ARGV:
    while ( my $arg = shift @ARGV ) {

        $arg =~ s/^\s+//; # rm leading spaces because we may get a quoted arg.
        #  e.g. quoted to protect > within v ' OpenSRS::DNS::Helper->magical_blank_zone_name '

        # Pass through args intended for vi e.g. -arg +123 or +/foo
        if ( $arg =~ /^[-+]/ ) {
            push @vi_args, $arg;
            next;
        }

        my ($found_file, $error, $last_search);

        # don't search file system if arg doesn't look like a file
        unless ( $arg =~ /file:.*line:/ || $arg =~ /^[^:]+:\d+$/ || $arg =~ /->/ ) {

            # if $arg is a file that exists.. then we're done.
            ($found_file, $error) = search_dirs( $last_search = $arg );
            if ( $found_file ) {
                if ( @ARGV >= 2 && $ARGV[0] eq 'line' && $ARGV[1] =~ /^(\d+)[\.,]?$/ ) {
                    # perl -c outputs stuff like "Global symbol "%args" requires explicit package name at DomainRates2.pm line 456."
                    # Say we copy and paste the last part "Module.pm  line 456."
                    push @vi_args, "+$1";
                    push @vi_args, $found_file;
                    $found_at_least_one_file = 1;
                    shift @ARGV;
                    shift @ARGV;
                    next;
                } else {
                    shift @ARGV;
                    push @vi_args, $found_file;
                    $found_at_least_one_file = 1;
                    next;
                }
            }
        }

        my @extracted_data = extract_file_and_line( $arg );

        while( my $extract = shift @extracted_data ) {

            my ($file, $line) = @{$extract};

            if ( (not defined $last_search) || $last_search ne $file ) {
                ($found_file, $error) = search_dirs($last_search = $file);
            }

            if ( $found_file ) {
                push @vi_args, "+$line" if $line;
                push @vi_args, $found_file;
                $found_at_least_one_file = 1;
                next WHILE_ARGV;
            }
        }

        if ( $found_at_least_one_file ) {

            if ( $arg =~ /,line:(\d+)/ ) {
                # e.g. v file://file, line:123
                if ( my $line = $1 ) {
                    my $file = pop @vi_args;
                    push @vi_args, "+$line";
                    push @vi_args, $file;
                }
                next WHILE_ARGV;
            }

            # e.g. grep -rn foo .
            # outputs stuff like
            #   file:123: foo
            # User selects entire line (via mouse tripple click) and runs
            #   v file:123: foo
            # Since we found file:123  ignore the rest of the args
            last WHILE_ARGV;
        }

        if ( @ARGV ) { # last attempt

            my @extraced_data = extract_file_and_line( join(" ", @ARGV) );
            while( my $extract = shift @extracted_data ) {

                my ($file, $line) = @{$extract};

                if ( (not defined $last_search) || $last_search ne $file ) {
                    ($found_file, $error) = search_dirs($last_search = $file);
                }

                if ( $found_file ) {
                    push @vi_args, "+$line" if $line;
                    push @vi_args, $found_file;
                    $found_at_least_one_file = 1;
                    last WHILE_ARGV;
                }
            }
        }

        $error //= "Heuristics failed to find file args=(@ARGV)\n";
        print $error;
        exit 1;
    }
    return \@vi_args;
}

sub extract_file_and_line {
    my $args = shift;
    my ($file, $line);
    my @additional_answers;

    # handle file:/path/filename,line:123 
    if ( $args =~ /file:(.*?)[, ]line:(\d+)/ ) {
        $file = $1;
        $line = $2;
    } elsif ( $args =~ /^(.*?)[, ]line:(\d+)/ ) {
        $file = $1;
        $line = $2;
    } elsif ( $args =~ /^(.*?)->(\w+)/ ) { #  "v Foo::Bar->baz"   ->   "vi Foo/Bar.pm +/sub\s\+baz\>"
        $file = $1 . '.pm';
        $line = '/sub\s\+' . $2 . '\>';
    } elsif ( $args =~ /^(.*?):(\d+)/ ) {
        $file = $1;
        $line = $2;
    } else {
        $file = $args;
    }
    if ( $file =~ /::/ ) {
        my @split = split('::', $file);
        my $arg = pop @split;
        if ( @split ) {
            my $join = join('/', @split);
            push @additional_answers, [
                $join . '.pm',
                '/sub\s\+' . $arg . '\>'
            ];
        }
    }
    $file =~ s!::!/!g;
    $file =~ s/^.*(module:|file:)//;
    if ( not defined $line ) {
        if ( $file =~ /^(.*?):(\d+)/ ) {
            $file = $1;
            $line = $2;
        } else {
            $file =~ s/:.*$//;
        }
    }
    $line //= 0;
    if ( @additional_answers ) {
        return [ $file, $line ], @additional_answers;
    }
    return [ $file, $line ];
}

sub search_dirs {
    my $file = shift;
    my @dirs = @INC;
    if ( $ENV{CONTROL_PANEL_HOME} && -d "$ENV{CONTROL_PANEL_HOME}/lib" ) {
        unshift @dirs, "$ENV{CONTROL_PANEL_HOME}/lib";
    }
    if ( $ENV{OPENSRS_HOME} && -d "$ENV{OPENSRS_HOME}/lib" ) {
        unshift @dirs, "$ENV{OPENSRS_HOME}/lib";
        unshift @dirs, "$ENV{OPENSRS_HOME}/lib/CatalystApp";
    }
    if ( -d "/home/mnieweglowski/price/code/pricing_admin/lib" ) {
        unshift @dirs, "/home/mnieweglowski/price/code/pricing_admin/lib";
    }
    unshift @dirs, ".";
    if ( $file =~ m!^/! ) { # #file is absolute
        unshift @dirs, "";
        $file =~ s!^/!!;
    }

    my $found_file;
    for my $dir ( @dirs ) {
        
        $dir =~ s!/$!!;
        my $dir_file = "$dir/$file";

        if ( -r $dir_file && ! -d $dir_file ) {
            $found_file = $dir_file;
            last;
        }
        if ( $dir_file !~ /\.pm$/ ) {
            my $dir_file_pm = $dir_file . ".pm";
            if ( -r $dir_file_pm && ! -d $dir_file_pm ) {
                $found_file = $dir_file_pm;
                last;
            }
            if ( $dir_file =~ /::/ ) {
                (my $dir_file_slash = $dir_file) =~ s!::!/!g;
                if ( -r $dir_file_slash && ! -d $dir_file_slash ) {
                    $found_file = $dir_file_slash;
                    last;
                }
                $dir_file_slash .= '.pm';
                if ( -r $dir_file_slash && ! -d $dir_file_slash ) {
                    $found_file = $dir_file_slash;
                    last;
                }
            }
        }

    }
    if ( not defined $found_file ) {
        if ( -d $file ) {
            return ( undef,  qq{File ($file) is a directory\n} );
        } else {
            return ( undef,  qq{File ($file) does not exist\n} );
        }
    }
    return ($found_file, undef);
}

sub get_vi_exec {
#    if ( `whoami` =~ /mnieweglowski/ ) {
#        return ["vi"];
#    } else {
#        return ["/usr/bin/vim", "-u", "/home/mnieweglowski/.vimrc"];
#    }
    if ( -e '/home/mnieweglowski/bin/vi.wrapper' ) { 
        return ['/home/mnieweglowski/bin/vi.wrapper'];
    } else {
        return ["vi"];
    }  
}

sub run_vi {
    my ($vi_args) = @_;

    my @cmd = ( @{get_vi_exec()}, @{$vi_args} );

    exec(@cmd) || die "Could not run @cmd: $!";
}

sub main {
    my ($vi_args) = parse_args();
    if ( $vi_args ) {
        run_vi( $vi_args );
    }
}

main();
