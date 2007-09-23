package CPAN::Reporter::History;
$VERSION = '0.99_12';
use strict; 
use Config;
use Fcntl qw/:flock :seek/;
use File::HomeDir (); 
use File::Path (qw/mkpath/);
use File::Spec ();
use File::Temp ();
use IO::File ();
use CPAN (); # for printing warnings
use CPAN::Reporter::Config ();

#--------------------------------------------------------------------------#
# Some platforms don't implement flock, so fake it if necessary
#--------------------------------------------------------------------------#

BEGIN {
    eval {
        my $fh = File::Temp->new() or return;
        flock $fh, LOCK_EX;
    };
    if ( $@ ) {
        *CORE::GLOBAL::flock = sub (*$) { 1 };
    }
}

#--------------------------------------------------------------------------#
# Back-compatibility checks -- just once per load
#--------------------------------------------------------------------------#


# 0.99_08 changed the history file format and name
# If an old file exists, convert it to the new name and format.  Note -- 
# someone running multiple installations of CPAN::Reporter might have old 
# and new versions running so only convert in the case where the old file
# exists and the new file does not

{
    my $old_history_file = _get_old_history_file();
    my $new_history_file = _get_history_file();
    last if -f $new_history_file || ! -f $old_history_file;

    $CPAN::Frontend->mywarn("Your CPAN::Reporter history file is in an old format. Upgrading automatically.\n");

    # open old and new files
    my ($old_fh, $new_fh);
    if (! ( $old_fh = IO::File->new( $old_history_file ) ) ) {
        $CPAN::Frontend->mywarn("Error opening old history file: $!\nContinuing without conversion.\n");
        last;
    }
    if (! ($new_fh = IO::File->new( $new_history_file, "w" ) ) ) {
        $CPAN::Frontend->mywarn("Error opening new history file: $!\nContinuing without conversion.\n");
        last;
    }

    print {$new_fh} "# Generated by CPAN::Reporter " .
                     "$CPAN::Reporter::Config::VERSION\n";
    while ( my $line = <$old_fh> ) {
        chomp $line;
        # strip off perl version and convert
        $line =~ s{ (\d\.\d+) ?(patch \d+)?$}{};
        my ($old_version, $perl_patch) = ($1, $2);
        my $pv = $old_version ? _perl_version($old_version) : "unknown perl";
        $pv .= " $perl_patch" if $perl_patch;
        my ($grade_dist, $arch_os) = ($line =~ /(\S+ \S+) (.+)/);
        print {$new_fh} "test $grade_dist (perl-$pv) $arch_os\n";
    }
    close $old_fh;
    close $new_fh;
}


#--------------------------------------------------------------------------#
# Public methods
#--------------------------------------------------------------------------#

#--------------------------------------------------------------------------#
# Private methods
#--------------------------------------------------------------------------#

#--------------------------------------------------------------------------#
# _format_history -- 
#
# phase grade dist-version (perl-version patchlevel) archname osvers
#--------------------------------------------------------------------------#

sub _format_history {
    my ($result) = @_;
    my $phase = $result->{phase};
    my $grade = uc $result->{grade};
    my $dist_name = $result->{dist_name};
    my $perlver = _format_perl_version();
    my $arch = "$Config{archname} $Config{osvers}";    
    return "$phase $grade $dist_name ($perlver) $arch\n";
}

#--------------------------------------------------------------------------#
# _format_perl_version
#--------------------------------------------------------------------------#

sub _format_perl_version {
    my $pv = "perl-" . _perl_version();
    $pv .= " patch $Config{perl_patchlevel}" 
        if $Config{perl_patchlevel};
    return $pv;
}

#--------------------------------------------------------------------------#
# _get_history_file
#--------------------------------------------------------------------------#

sub _get_history_file {
    return File::Spec->catdir( 
        CPAN::Reporter::Config::_get_config_dir(), "reports-sent.db" 
    );
}

#--------------------------------------------------------------------------#
# _get_old_history_file -- prior to 0.99_08
#--------------------------------------------------------------------------#

sub _get_old_history_file {
    return File::Spec->catdir( 
        CPAN::Reporter::Config::_get_config_dir(), "history.db" 
    );
}

#--------------------------------------------------------------------------#
# _is_duplicate
#--------------------------------------------------------------------------#

sub _is_duplicate {
    my ($result, $subject) = @_;
    my $log_line = _format_history( $result, $subject );
    my $history = _open_history_file('<') or return;
    my $found = 0;
    flock $history, LOCK_SH;
    while ( defined (my $line = <$history>) ) {
        $found++, last if $line eq $log_line
    }
    $history->close;
    return $found;
}

#--------------------------------------------------------------------------#
# _open_history_file
#--------------------------------------------------------------------------#

sub _open_history_file {
    my $mode = shift || '<';
    my $history_filename = _get_history_file();
    my $file_exists = -f $history_filename;

    # shortcut if reading and doesn't exist
    return if ( $mode eq '<' && ! $file_exists );

    # open it in the desired mode
    my $history = IO::File->new( $history_filename, $mode )
        or $CPAN::Frontend->mywarn("Couldn't open CPAN::Reporter history file "
        . "'$history_filename': $!\n");
    
    # if writing and it didn't exist before, initialize with header
    if ( substr($mode,0,1) eq '>' && ! $file_exists ) {
        print {$history} "# Generated by CPAN::Reporter " .
                         "$CPAN::Reporter::Config::VERSION\n";
    }

    return $history; 
}

#--------------------------------------------------------------------------#
# _perl_version
#--------------------------------------------------------------------------#

sub _perl_version {
    my $ver = shift || "$]";
    $ver =~ qr/(\d)\.(\d{3})(\d{0,3})/;
    my ($maj,$min,$pat) = (0 + $1, 0 + $2, 0 + ($3||0));
    my $pv;
    if ( $min < 6 ) {
        $pv = $ver;
    }
    else {
        $pv = "$maj\.$min\.$pat";
    }
    return $pv;
}

#--------------------------------------------------------------------------#
# _record_history
#--------------------------------------------------------------------------#

sub _record_history {
    my ($result, $subject) = @_;
    my $log_line = _format_history( $result, $subject );
    my $history = _open_history_file('>>') or return;

    flock( $history, LOCK_EX );
    seek( $history, 0, SEEK_END );
    $history->print( $log_line );
    flock( $history, LOCK_UN );
    
    $history->close;
    return;
}

1;
__END__

=begin wikidoc

= NAME

CPAN::Reporter::History - Read or write a CPAN::Reporter history log

= VERSION

This documentation refers to version %%VERSION%%

= SYNOPSIS


= DESCRIPTION


= SEE ALSO

* [CPAN::Reporter]
* [CPAN::Reporter::FAQ]

= AUTHOR

David A. Golden (DAGOLDEN)

= COPYRIGHT AND LICENSE

Copyright (c) 2006, 2007 by David A. Golden

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at 
[http://www.apache.org/licenses/LICENSE-2.0]

Files produced as output though the use of this software, including
generated copies of boilerplate templates provided with this software,
shall not be considered Derivative Works, but shall be considered the
original work of the Licensor.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=end wikidoc

