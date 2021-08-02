package Setup::File::Line;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_file_line);

our %SPEC;

$SPEC{setup_file_line} = {
    v           => 1.1,
    summary     => 'Insert/delete a line in a file (with undo support)',
    description => <<'_',

1. On do (and when `should_exist` is true): will insert a specified line to file
at the end. There's an option to add line at the top instead (set `top_style` to
true). Will not add line if line already exists. There's an option to do
case-insensitive matching when checking for existence of line.

Unfixable state: file does not exist or not a regular file (directory and
symlink included) or not open-able for read/write.

Fixed state: file exists, line already exists in file.

Fixable state: file exists, line doesn't exist.


2. On do (and when `should_exist` is false): will remove specified line from the
file. All occurence of the line will be removed.

Unfixable state: file does not exist or not a regular file (directory and
symlink included) or not open-able for read/write.

Fixed state: file exists, line already does not exist in file.

Fixable state: file exists, line exists in file.


Note that unlike <pm:Setup::File::TextFragment>'s `setup_text_fragment`, this
routine does save/restore original file content on undo. Instead, this routine
will delete all lines with same content when undoing an add, and adding a line
when undoing a delete. This means the file might not be restored to an identical
previous content upon undo.

_
    args        => {
        path => {
            summary => 'Path to file',
            schema => 'str*',
            req    => 1,
            pos    => 0,
        },
        line_content => {
            summary => 'Line (without the newline; newline will be stripped first)',
            schema => 'str*',
            req    => 1,
            pos    => 1,
        },
        case_insensitive => {
            schema => 'bool',
            cmdline_aliases => {i=>{}},
        },
        top_style => {
            summary => 'If set to true, will insert at the top of file instead of at the end',
            schema => 'bool',
        },
        should_exist => {
            summary => 'Whether line should exist',
            schema => [bool => {default=>1}],
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub setup_file_line {
    my %args = @_;

    # TMP, schema
    my $tx_action        = $args{-tx_action} // '';
    my $taid             = $args{-tx_action_id}
        or return [400, "Please specify -tx_action_id"];
    my $dry_run          = $args{-dry_run};
    my $path             = $args{path};
    defined($path) or return [400, "Please specify path"];
    my $line_content     = $args{line_content};
    defined($line_content) or return [400, "Please specify line_content"];
    $line_content =~ s/\R//g;
    my $top_style        = $args{top_style};
    my $should_exist     = $args{should_exist} // 1;
    my $case_insensitive = $args{case_insensitive};

    my $is_sym  = (-l $path);
    my @st      = stat($path);
    my $exists  = $is_sym || (-e _);
    my $is_file = (-f _);

    my @cmd;

    return [412, "$path does not exist"] unless $exists;
    return [412, "$path is not a regular file"] if $is_sym||!$is_file;

    open my($fh), "<", $path or return [500, "Can't open file '$path': $!"];
    my $content = do { local $/; scalar <$fh> };

    # return 304 if in fixed state
    if ($should_exist) {
        if ($case_insensitive ?
                $content =~ /^\Q$line_content\E$/im :
                $content =~ /^\Q$line_content\E$/m) {
            # line already exists, do nothing
            return [304, "Line already exists in file"];
        }
    } else {
        if ($case_insensitive ?
                $content !~ /^\Q$line_content\E$/im :
                $content !~ /^\Q$line_content\E$/m) {
            # line already does not exist, do nothing
            return [304, "Line already does not exist in file"];
        }
    }

    if ($tx_action eq 'check_state') {
        if ($should_exist) {
            log_info("(DRY) Inserting line '$line_content' to file '$path' ...")
                if $dry_run;
            return [200, "Line '$line_content' needs to be added to file '$path'", undef,
                    {undo_actions=>[
                        ['Setup::File::Line::setup_file_line', # delete line
                         {path=>$path, should_exist=>0, top_style=>$top_style, case_insensitive=>$case_insensitive, line_content=>$line_content}],
                    ]}];
        } else {
            log_info("(DRY) Deleting line '$line_content' (all occcurences) from file '$path' ...") if $dry_run;
            return [200, "Line '$line_content' needs to be deleted to file '$path'", undef,
                    {undo_actions=>[
                        ['Setup::File::Line::setup_file_line', # delete line
                         {path=>$path, should_exist=>1, top_style=>$top_style, case_insensitive=>$case_insensitive, line_content=>$line_content}],
                    ]}];
        }
    } elsif ($tx_action eq 'fix_state') {
        require File::Slurper::Temp;
        if ($should_exist) {
            log_info("Inserting line '$line_content' to file '$path' ...");
            File::Slurper::Temp::modify_text(
                $path, sub {
                    $_ =
                        $top_style ?
                        "$line_content\n$_" :
                        length($_) ? $_ . (/\R\z/ ? "" : "\n") . $line_content . "\n" : "$line_content\n";
                    1;
                },
            );
            return [200, "OK"];
        } else {
            log_info("Deleting line '$line_content' (all occurrences) from file '$path' ...");
            File::Slurper::Temp::modify_text(
                $path, sub {
                    if ($case_insensitive) {
                        s/^\Q$line_content\E(?:\R|\z)//gim;
                    } else {
                        s/^\Q$line_content\E(?:\R|\z)//gm;
                    }
                    1;
                },
            );
            return [200, "OK"];
        }
    }
    [400, "Invalid -tx_action"];
}

1;
# ABSTRACT:

=head1 DESCRIPTION

Experimental.


=head1 SEE ALSO

Other modules to setup file content: L<Setup::File::Edit>,
L<Setup::File::TextFragment>.

The Setup framework: L<Setup>

=cut
