#!/usr/bin/perl

use strict;
use warnings;
use Cwd;
use File::Find ();

my $dir = $ARGV[0] || 'wiki';

if ( !-d $dir ) {
    warn "Sorry, $dir is not a valid directory: $!";
    exit 1;
}
chdir $dir or die "Failed to chdir into \'$dir\': $!";

# Reset $dir to an absolute path
$dir = Cwd::getcwd();

my $file_name_match = '\.html?$';

print "Checking directory \'$dir\' for files matching regex \'$file_name_match\'.\n";

my @files = qw();
my %file_renames;

File::Find::find( \&wanted, $dir );

# Regexes
my $body_begin_regex   = qr/class="pageheader"/;
my $footer_begin_regex = qr/<table border="0" cellpadding="0" cellspacing="0" width="100%">/;
my $attachements_regex = qr/<div class="greybox" align="left">/;
my $panel_macro_regex =
    qr{<div class='panelMacro'><table class='(?:info|note|warning)Macro'><colgroup><col width='24'><col></colgroup><tr><td valign='top'><img src="images/icons/emoticons/(information|warning|forbidden).gif" width="16" height="16" align="absmiddle" alt="" border="0"></td><td>(.+)};
my $image_regex = qr{<span class="image-wrap" style=""><img src="([^"]+)" style="border: 0px solid black"/></span>};

my $header = get_tmpl_contents( 'header.tmpl', $dir );
my $footer = get_tmpl_contents( 'footer.tmpl', $dir );

my $count = 0;
foreach my $file (@files) {

    if ( open my $fh, '+<', $file ) {
        print "Checking $file";

        my @dir_parts = split '/', $file;
        pop @dir_parts;
        my $file_dir = join '/', @dir_parts;

        chdir $file_dir or die "Failed to chdir into $file_dir: $!";

        my @lines;
        my $doc_title     = '';
        my $end_header    = 0;
        my $end_body      = 0;
        my $modified_file = 0;
        while ( my $line = <$fh> ) {
            if ($end_body) {
                $modified_file++;
                next;
            }
            if ( !$end_header ) {
                if ( $line =~ m/$body_begin_regex/ ) {

                    $end_header = 1;

                    # Capture document title and ignore rest
                    <$fh>;
                    $doc_title = <$fh>;
                    $doc_title =~ s/^\s+//;
                    $doc_title =~ s/\s+$//;
                    <$fh>;
                    <$fh>;

                    # Remove document subheading
                    <$fh>;
                    <$fh>;
                    <$fh>;
                    $modified_file++;
                    next;

                }
                else {
                    $modified_file++;
                    next;
                }
            }
            if ( !$end_body ) {
                if ( $line =~ m/$footer_begin_regex/ ) {
                    $end_body = 1;

                    # Remove previous 3 lines once we see the footer identifier
                    pop @lines;
                    pop @lines;
                    pop @lines;
                    $modified_file++;
                }
                else {
                    # Fix panelMacro from wiki
                    if ( $line =~ m/$panel_macro_regex/ ) {
                        my $panel_note_header = '';
                        my $panel_type        = ( $1 eq 'warning' || $2 eq 'forbidden' ) ? 'caution' : 'note';
                        my $panel_note        = $2;

                        my $fixed_panelMacro;
                        if ( $panel_note =~ m/\<b\>([^<]+)\<\/b\>\<br\s\/\>(.+)/s ) {
                            $panel_note_header = $1;
                            $panel_note        = $2;
                        }
                        if ( $panel_note =~ m/(.+)\<\/td\>\s*\<\/tr\>\s*\<\/table\>\s*\<\/div\>/s ) {
                            $panel_note       = $1;
                            $fixed_panelMacro = 1;
                        }
                        else {
                            # Handle multi-line panelMacro div
                        PANEL_LINE: while ( my $panel_note_rem_line = <$fh> ) {
                                $line       .= $panel_note_rem_line;
                                $panel_note .= $panel_note_rem_line;
                                if ( $panel_note =~ m/(.+)\<\/td\>\s*\<\/tr\>\s*\<\/table\>\s*\<\/div\>/s ) {
                                    $panel_note       = $1;
                                    $fixed_panelMacro = 1;
                                    last PANEL_LINE;
                                }
                            }
                        }
                        if ($fixed_panelMacro) {
                            $line =~ m/\<\/td\>\s*\<\/tr\>\s*\<\/table\>\s*\<\/div\>(.+)/s;
                            $line = qq{<p class="$panel_type" MadCap:autonum="&lt;b&gt;$panel_note_header: &#160;&lt;/b&gt;">$panel_note</p>$1};
                            $modified_file++;
                        }
                        else {
                            warn "\nFailed to modify panelMacro in file $file\nLine: $line\n";
                        }
                    }

                    # Images
                    if ( $line =~ m{$image_regex} ) {

                        my $current_wd = Cwd::getcwd();

                        my $old_path = $1;
                        my $new_path = $1;
                        $new_path =~ s/^attachments/Resources\/images/;

                        if ( !-e $file_dir . '/Resources/images' ) {
                            system 'mkdir', '-p', $file_dir . '/Resources/images';
                        }

                        my @dir_parts = split( '/', $new_path );
                        pop @dir_parts;
                        my $new_dir = 'Resources/images/' . pop @dir_parts;

                        my $real_dir = -e $new_dir ? $new_dir : $file_dir . '/' . $new_dir;
                        if ( !-e $real_dir ) {
                            system 'mkdir', '-p', $real_dir;
                        }

                        my $real_new_path = -e $new_path ? $new_path : $file_dir . '/' . $new_path;
                        my $real_old_path = -e $old_path ? $old_path : $file_dir . '/' . $old_path;
                        if ( !-e $real_new_path ) {
                            system 'git', 'mv', $real_old_path, $real_new_path;
                        }

                        $line =~ s{$image_regex}{<p class="Img"><img src="$new_path" /></p>};
                    }

                    if ( my @matches = ( $line =~ m/href=['"]([^'"]+)['"]/g ) ) {
                        foreach my $link_doc (@matches) {
                            my $clean_link_doc = $link_doc;
                            $clean_link_doc =~ s/#.+$//;

                            my $new_clean_link_doc = $clean_link_doc;
                            $new_clean_link_doc =~ s/\s+/_/g;

                            my $fix_href;
                            if ( -e $clean_link_doc ) {
                                $fix_href = 1;
                            }

                            if ($fix_href) {
                                $line =~ s/$clean_link_doc/$new_clean_link_doc/g;
                                $file_renames{ $file_dir . '/' . $clean_link_doc } = $file_dir . '/' . $new_clean_link_doc;
                            }
                        }

                    }

                    push @lines, $line;
                }
                if ( $line =~ m/$attachements_regex/ ) {

                    $end_body = 1;

                    # Remove previous 7 lines once we see the attachments list
                    pop @lines;
                    pop @lines;
                    pop @lines;
                    pop @lines;
                    pop @lines;
                    pop @lines;
                    pop @lines;
                    pop @lines;

                    $modified_file++;
                }
            }
        }

        unshift @lines, qq{<head><title>$doc_title</title>\n    </head>\n    <body>\n        <h1>$doc_title</h1>\n};

        seek( $fh, 0, 0 );
        print {$fh} $header, @lines, $footer;
        truncate( $fh, tell($fh) );
        close $fh;

        if ($modified_file) {
            $count++;
            print " ... Modified!\n";
        }
        else {
            print "\n";
        }
    }
    else {
        die "Unable to open $file for read/write: $!";
    }
}

print "\nModified $count files\n";

foreach my $file ( sort keys %file_renames ) {
    if ( $file ne $file_renames{$file} ) {
        print "Renaming $file -> $file_renames{$file}\n";
        system 'git', 'mv', $file, $file_renames{$file};
    }
}

sub wanted {
    if (m/$file_name_match/o) {
        push @files, $File::Find::name;
    }
}

sub get_tmpl_contents {
    my ( $file, $dir ) = @_;
    if ( -e $file ) {
        warn "Using template file $file in the current working directory\n";
    }
    else {
        $file = $dir . '/' . $file;
    }
    my $data;
    if ( open my $fh, '<', $file ) {
        local $/ = undef;
        $data = <$fh>;
        close $fh;
    }
    else {
        die "Failed to read $file: $!";
    }
    return $data;
}
