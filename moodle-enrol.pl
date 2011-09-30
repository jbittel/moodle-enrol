#!/usr/bin/perl -w

#
# Copyright (c) 2011, Corban College <jbittel@corban.edu>. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the author nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COLLEGE OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

use strict;
use warnings;
use DBI;
use Getopt::Long;
use File::Basename;

# Active terms to process for enrollments; existing
# enrollments outside these terms are ignored.
my @TERMS = qw/20093 20094 20101 20103/;

# Enrollments with these grades, although existing 
# in the CA enrollment table, are ignored.
my @DROP_GRADES = qw/W/;

# These need to match the corresponding roles within
# your Moodle system.
my $TEACHER_ROLE = 'editingteacher';
my $STUDENT_ROLE = 'student';

# Configure database connection parameters...
# ...for Converge enrollment DB
my %DB_ENROL = (
    'type' => 'mysql',
    'db'   => 'enrol',
    'host' => 'localhost',
    'port' => '',
    'user' => '',
    'pass' => '',
);

# ...for CampusAnyware DB
my %DB_CA = (
    'type' => 'Sybase',
    'db'   => 'server=CampusAnyware',
    'host' => '',
    'port' => '',
    'user' => '',
    'pass' => '',
);

my $ENROL_FLATFILE = dirname($0) . "/enrol.txt";
my $MASTER_FILE = dirname($0) . "/master.txt";

my $TERMS = join ', ', map { qq/'$_'/ } @TERMS;
my $DROP_GRADES = join ', ', map { qq/'$_'/ } @DROP_GRADES;

# Command line options
my $dump_ca = '';
my $dump_enrol = '';
my $dry_run = '';

my @curr_ca = ();
my @curr_enrol = ();

GetOptions("dry-run" => \$dry_run,
           "dump-enrol" => \$dump_enrol,
           "dump-ca" => \$dump_ca);

if ($dump_enrol) {
    get_moodle_enrollments(\@curr_enrol);
    print_array(\@curr_enrol);
    exit;
}

if ($dump_ca) {
    get_ca_enrollments(\@curr_ca);
    print_array(\@curr_ca);
    exit;
}

get_moodle_enrollments(\@curr_enrol);
get_ca_enrollments(\@curr_ca);

process_enrollments(\@curr_ca, \@curr_enrol);

sub get_moodle_enrollments {
    my $curr_enrol = shift;
    my $sql;
    my $sth;
    my $row;

    my $dbh = connect_db(%DB_ENROL);

    $sql = qq{ SELECT role_name, userid, course_number
               FROM moodle
               WHERE RIGHT(course_number, 5) IN ($TERMS)
             };

    $sth = execute_query($dbh, $sql);

    while ($row = $sth->fetchrow_arrayref) {
        my ($role, $user, $course) = map { s/^\s+//; s/\s+$//; $_ } @$row;
        next if (!$role or !$user or !$course);

        push @$curr_enrol, join ',', $role, $user, $course;
    }

    disconnect_db($dbh);

    return;
}

sub get_ca_enrollments {
    my $curr_ca = shift;
    my $sql;
    my $sth;
    my $row;
    my %master;

    # Build lookup table for course combination requests
    get_course_masters(\%master);

    my $dbh = connect_db(%DB_CA);

    # Retrieve instructor enrollments from DB
    $sql = qq{ SELECT srcrinst_instruct_code, srcrinst_course_code + srcrinst_term_code
               FROM srcrinst
               WHERE srcrinst_term_code IN ($TERMS)
             };

    $sth = execute_query($dbh, $sql);

    while ($row = $sth->fetchrow_arrayref) {
        my ($user, $course) = map { s/^\s+//; s/\s+$//; s/\,//; $_ } @$row;
        next if (!$user or !$course);

        # If a master course exists, remap the course number
        if (exists $master{$course}) {
            $course = $master{$course};
        }

        push @$curr_ca, join ',', $TEACHER_ROLE, $user, $course;
    }

    # Retrieve student enrollments from DB
    $sql = qq{ SELECT srenroll_student_id, srenroll_course_code + srenroll_term_code
               FROM srenroll
               WHERE srenroll_term_code IN ($TERMS)
               AND (srenroll_final IS NULL OR srenroll_final NOT IN ($DROP_GRADES))
             };

    $sth = execute_query($dbh, $sql);

    while ($row = $sth->fetchrow_arrayref) {
        my ($user, $course) = map { s/^\s+//; s/\s+$//; s/\,//; $_ } @$row;
        next if (!$user or !$course);

        # If a master course exists, remap the course number
        if (exists $master{$course}) {
            $course = $master{$course};
        }

        push @$curr_ca, join ',', $STUDENT_ROLE, $user, $course;
    }

    disconnect_db($dbh);

    return;
}

sub get_course_masters {
    my $master = shift;
    my $line;
    my $course;
    my $term;

    return if (!-e $MASTER_FILE);

    open MASTER, '<', "$MASTER_FILE" or die "Cannot open file: $!";
    while ($line = <MASTER>) {
        $line = strip($line);
        next if $line =~ /^$/;

        my ($master_course, @sub_courses) = split /\s/, $line;
        next unless within_active_terms($master_course);

        foreach $course (@sub_courses) {
            # If sub-course has an '*' instead of
            # a term, apply to all active terms
            if ($course =~ /^([A-Z0-9]{9})\*$/) {
                $course = $1;

                foreach $term (@TERMS) {
                    $$master{$course.$term} = $master_course;
                }
            } else {
                next unless within_active_terms($course);
                $$master{$course} = $master_course;
            }
        }
    }
    close MASTER;

    return;
}

sub process_enrollments {
    my $curr_ca = shift;
    my $curr_enrol = shift;
    my %ca;
    my %enrol;
    my @diff;
    my $tuple;

    # Build lookup tables
    @ca{@$curr_ca} = ();
    @enrol{@$curr_enrol} = ();

    # In CA and not enrol: add enrollment
    foreach $tuple (@$curr_ca) {
        next if (exists $enrol{$tuple});
        push @diff, "add,$tuple";
    }

    # Not in CA and in enrol: delete enrollment
    foreach $tuple (@$curr_enrol) {
        next if (exists $ca{$tuple});
        push @diff, "del,$tuple";
    }

    if ($dry_run) {
        print_array(\@diff);
    } else {
        update_enrol_db(\@diff);
        put_enrol_flatfile(\@diff);
    }

    return;
}

sub update_enrol_db {
    my $diff = shift;
    my $dbh;
    my $sql;

    $dbh = connect_db(%DB_ENROL);

    foreach (@$diff) {
        my ($action, $role, $user, $course) = split ',';
        $user =~ s/'/\\'/; # Handle teacher IDs with ' characters

        if ($action eq 'add') {
            $sql = qq{ INSERT IGNORE INTO moodle (userid, course_number, role_name)
                       VALUES ('$user', '$course', '$role')
                     };
        } else {
            $sql = qq{ DELETE FROM moodle
                       WHERE userid = '$user'
                       AND course_number = '$course'
                       AND role_name = '$role'
                     };
        }

        execute_query($dbh, $sql);
    }

    $dbh->commit or die "Error committing data: " . DBI->errstr;

    disconnect_db($dbh);

    return;
}

sub put_enrol_flatfile {
    my $diff = shift;

    return if (scalar @$diff == 0);

    open ENROL, '>>', "$ENROL_FLATFILE" or die "Cannot open file: $!";
    foreach (@$diff) {
        print ENROL "$_\n";
    }
    close ENROL;

    return;
}

sub connect_db {
    my %db = @_;
    my $dbh;

    my $dsn = join ':', 'DBI', $db{'type'}, $db{'db'};
    $dsn = $dsn . ":$db{'host'}" if $db{'host'};
    $dsn = $dsn . ":$db{'port'}" if $db{'port'};

    $dbh = DBI->connect($dsn, $db{'user'}, $db{'pass'}, { RaiseError => 1,
                                                          AutoCommit => 0,
                                                          syb_chained_txn => 1 })
            or die "Error connecting to database: " . DBI->errstr;

    if ($db{'db'} =~ /.+\=(.+)/) {
        $db{'db'} = $1;
    }

    execute_query($dbh, qq{ USE $db{'db'} } );

    return $dbh;
}

sub disconnect_db {
    my $dbh = shift;

    $dbh->disconnect;

    return;
}

sub execute_query {
    my $dbh = shift;
    my $sql = shift;
    my $sth;

    $sth = $dbh->prepare($sql) or die "Error preparing query: " . DBI->errstr;
    $sth->execute() or die "Error executing query: " . DBI->errstr;

    return $sth;
}

sub print_array {
    my $array = shift;

    foreach (@$array) {
        print "$_\n";
    }

    return;
}

sub strip {
    my $str = shift;

    chomp $str;
    $str =~ s/\#.*$//; # Remove comments
    $str =~ s/^\s+//;  # Remove leading whitespace
    $str =~ s/\s+$//;  # Remove trailing whitespace
    $str =~ s/\s+/ /;  # Remove sequential whitespace

    return $str;
}

sub within_active_terms {
    my $course = shift;

    # If not a full course number, assume ok as
    # there's no term to check against
    if (length($course) < 14) {
        return 1;
    }

    my $term = substr $course, -5;

    return grep { $_ eq $term } @TERMS;
}
