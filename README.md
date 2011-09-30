The Situation
=============

We are currently running both Campus Anyware and Moodle, and needed to be able to synchronize course enrollments between the two systems. The registrar's office should be the authoritative source for course enrollments, and it is too error-prone and time consuming to have faculty manually enroll their students in each course.

Moodle Access
=============

Some of our course creation strategies really helped in finding a solution. Instead of reusing the same course shells every semester, we import a new Moodle course for each course instance in CA. This means that each course has both a short name and ID number of the course number and term, so it is unique within the system (e.g. IS202000120101). Our user authentication is handled through LDAP, and when we create a profile in Moodle, we insert the individual's ID number. These two pieces allow us to uniquely identify both a course and an individual within Moodle.

Campus Anyware Access
=====================

There is no external API access to CA, so we need to dig directly into the database to extract the current enrollment data.

Moodle Enrollment Plugins
=========================

Moodle provides a number of ways to process course enrollments automatically. We chose to use two of these enrollment plugins:

1. [External database](http://docs.moodle.org/20/en/External_database_enrolment "External database enrollment")
2. [Flat file](http://docs.moodle.org/20/en/Flat_file "Flat file enrollment")

The Moodle documentation for each of these plugins has a great deal of information about how they work and how to implement them.

We chose to use two enrollment plugins to cover all of the corner cases for enrollments. Just using database enrollments works fine, but enrollments are processed at login. This meant many instructors were left wondering why some of their students weren't enrolled immediately and led to much confusion. But at the same time, you cannot rely on one-time flat file enrollments or any enrollments where the course or user wasn't available would mean they never got processed. Depending on your setup, you can also utilize the Moodle [external database synchronization script](http://docs.moodle.org/20/en/External_database_enrolment#Synchronization_Script "External database synchronization script") instead of the flat file enrollment plugin. In our experience it does essentially the same thing, but can take more time to process. However, it might be a simpler solution to the problem in some cases.

Another Wrinkle
===============

We also had another need to handle within the process. A number of our faculty teach multiple sections of a single course and run identical Moodle courses for each section. Understandably, they do not want to have to update multiple sections of identical content and would rather just deal with a single section within Moodle. To meet this need, we handle course combinations when reading the enrollments from the CA database. There's a separate text file that contains multiple course numbers on each line. The first number on the line is the course "master" and all enrollments pointing to the other course numbers will be modified to point to that master course. As this translation is handled while reading in the current enrollments from CA, the process is entirely transparent to both systems.

The Glue
========

We wrote a Perl script to tie these two systems together. While designed as a bridge between Campus Anyware and Moodle, it could easily be modified to pull from some other system. At a high level, the logic goes something like this:

1. Retrieve current Moodle enrollments
2. Retrieve current Campus Anyware enrollments, while processing any course combinations
3. If the enrollment is in CA but not Moodle, add it
4. If the enrollment is not in CA but in Moodle, delete it
5. Update an external enrollment database
6. Output a flat file of changed items

Script Settings
===============

At the top of the Perl script are a few settings that need to be configured. These are all commented and should be fairly self-explanatory.

```perl
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
```
