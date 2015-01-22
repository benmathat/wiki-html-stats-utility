#!/usr/bin/perl

use strict;
use warnings;
use File::Find ();

my $dir = $ARGV[0] || '.';

if ( !-d $dir ) {
    warn "Sorry, $dir is not a valid directory: $!";
    exit 1;
}

my $file_name_match = '\.html?$';

print "Checking directory \'$dir\' for files matching regex \'$file_name_match\'.\n";

my @files = qw();

File::Find::find( \&wanted, $dir );

my $body_begin_regex   = qr/class="pageheader"/;
my $footer_begin_regex = qr/<table border="0" cellpadding="0" cellspacing="0" width="100%">/;
my $attachements_regex = qr/<div class="greybox" align="left">/;
my $panel_macro_regex =
    qr{<div class='panelMacro'><table class='infoMacro'><colgroup><col width='24'><col></colgroup><tr><td valign='top'><img src="images/icons/emoticons/information.gif" width="16" height="16" align="absmiddle" alt="" border="0"></td><td>(.+)};

my $header = get_tmpl_contents( 'header.tmpl', $dir );
my $footer = get_tmpl_contents( 'footer.tmpl', $dir );

my $count = 0;
foreach my $file (@files) {
    if ( open my $fh, '+<', $file ) {
        print "Checking $file";
        my @lines;
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

                    # print "\n\nbody_begin_regex matched\n\n";
                    $end_header = 1;
                }
                else {
                    # print "\nSkipping header: $line";
                    $modified_file++;
                    next;
                }
            }
            if ( !$end_body ) {
                if ( $line =~ m/$footer_begin_regex/ ) {

                    # print "\n\nfooter_begin_regex matched\n\n";
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
                        my $panel_note        = $1;

#<div class='panelMacro'><table class='infoMacro'><colgroup><col width='24'><col></colgroup><tr><td valign='top'><img src="images/icons/emoticons/information.gif" width="16" height="16" align="absmiddle" alt="" border="0"></td><td><b>Tip</b><br />To find a Task, you can use the Basic and Advanced List Filters. See <a href="Customize the Task History list.html" title="Customize the Task History list">Customize the Task History list</a>.</td></tr></table></div>


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
                            # Handle multi-line panelMacro
                        PANEL_LINE: while ( my $panel_note_rem_line = <$fh> ) {
                                $line .= $panel_note_rem_line;
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
                            $line = qq{<p class="note" MadCap:autonum="&lt;b&gt;$panel_note_header: &#160;&lt;/b&gt;">$panel_note</p>$1};
                            $modified_file++;
                        }
                        else {
                            warn "\nFailed to modify panelMacro in file $file\nLine: $line\n";
                        }
                    }
                    push @lines, $line;
                }
                if ( $line =~ m/$attachements_regex/ ) {

                    # print "\n\nattachements_regex\n\n";
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

        # last if $count;
    }
    else {
        die "Unable to open $file for read/write: $!";
    }
}

print "\nModified $count files\n";

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
