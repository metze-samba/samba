#!/usr/bin/perl
# Generate loadparm interfaces tables for Samba3/Samba4 integration
# by Andrew Bartlett
# based on mkproto.pl Written by Jelmer Vernooij
# based on the original mkproto.sh by Andrew Tridgell

use strict;

# don't use warnings module as it is not portable enough
# use warnings;

use Getopt::Long;
use File::Basename;
use File::Path;

#####################################################################
# read a file into a string

my $file = undef;
my $public_define = undef;
my $_public = "";
my $_private = "";
my $public_data = \$_public;
my $builddir = ".";
my $srcdir = ".";

sub public($)
{
	my ($d) = @_;
	$$public_data .= $d;
}

sub usage()
{
	print "Usage: mks3param.pl [options] [c files]\n";
	print "OPTIONS:\n";
	print "  --srcdir=path          Read files relative to this directory\n";
	print "  --builddir=path        Write file relative to this directory\n";
	print "  --help                 Print this help message\n\n";
	exit 0;
}

GetOptions(
	'file=s' => sub { my ($f,$v) = @_; $file = $v; },
	'srcdir=s' => sub { my ($f,$v) = @_; $srcdir = $v; },
	'builddir=s' => sub { my ($f,$v) = @_; $builddir = $v; },
	'help' => \&usage
) or exit(1);

sub normalize_define($$)
{
	my ($define, $file) = @_;

	if (not defined($define) and defined($file)) {
		$define = "__" . uc($file) . "__";
		$define =~ tr{./}{__};
		$define =~ tr{\-}{_};
	} elsif (not defined($define)) {
		$define = '_S3_PARAM_H_';
	}

	return $define;
}

$public_define = normalize_define($public_define, $file);

sub file_load($)
{
    my($filename) = @_;
    local(*INPUTFILE);
    open(INPUTFILE, $filename) or return undef;
    my($saved_delim) = $/;
    undef $/;
    my($data) = <INPUTFILE>;
    close(INPUTFILE);
    $/ = $saved_delim;
    return $data;
}

sub print_header($$)
{
	my ($file, $header_name) = @_;
	$file->("#ifndef $header_name\n");
	$file->("#define $header_name\n\n");
	$file->("/* This file was automatically generated by mks3param.pl. DO NOT EDIT */\n\n");
	$file->("struct loadparm_s3_helpers\n");
	$file->("{\n");
	$file->("\tconst char * (*get_parametric)(struct loadparm_service *, const char *type, const char *option);\n");
	$file->("\tstruct parm_struct * (*get_parm_struct)(const char *param_name);\n");
	$file->("\tvoid * (*get_parm_ptr)(struct loadparm_service *service, struct parm_struct *parm);\n");
	$file->("\tstruct loadparm_service * (*get_service)(const char *service_name);\n");
	$file->("\tstruct loadparm_service * (*get_default_loadparm_service)(void);\n");
	$file->("\tstruct loadparm_service * (*get_servicebynum)(int snum);\n");
	$file->("\tint (*get_numservices)(void);\n");
	$file->("\tbool (*load)(const char *filename);\n");
	$file->("\tbool (*set_cmdline)(const char *pszParmName, const char *pszParmValue);\n");
	$file->("\tvoid (*dump)(FILE *f, bool show_defaults, int maxtoprint);\n");
}

sub print_footer($$) 
{
	my ($file, $header_name) = @_;
	$file->("};");
	$file->("\n#endif /* $header_name */\n\n");
}

sub handle_loadparm($$) 
{
	my ($file,$line) = @_;

	# Local parameters don't need the ->s3_fns because the struct
	# loadparm_service is shared and lpcfg_service() checks the ->s3_fns
	# hook
	#
	# STRING isn't handled as we do not yet have a way to pass in a memory context nor
	# do we have a good way of dealing with the % macros yet.

	if ($line =~ /^FN_(GLOBAL)_(CONST_STRING|BOOL|bool|CHAR|INTEGER|LIST)\((\w+),.*\)/o) {
		my $scope = $1;
		my $type = $2;
		my $name = $3;

		my %tmap = (
			    "BOOL" => "bool ",
			    "CONST_STRING" => "const char *",
			    "STRING" => "const char *",
			    "INTEGER" => "int ",
			    "CHAR" => "char ",
			    "LIST" => "const char **",
			    );

		$file->("\t$tmap{$type} (*$name)(void);\n");
	}
}

sub process_file($$) 
{
	my ($file, $filename) = @_;

	$filename =~ s/\.o$/\.c/g;

	if ($filename =~ /^\//) {
		open(FH, "<$filename") or die("Failed to open $filename");
	} elsif (!open(FH, "< $builddir/$filename")) {
	    open(FH, "< $srcdir/$filename") || die "Failed to open $filename";
	}

	my $comment = undef;
	my $incomment = 0;
	while (my $line = <FH>) {	      
		if ($line =~ /^\/\*\*/) { 
			$comment = "";
			$incomment = 1;
		}

		if ($incomment) {
			$comment .= $line;
			if ($line =~ /\*\//) {
				$incomment = 0;
			}
		} 

		# these are ordered for maximum speed
		next if ($line =~ /^\s/);
	      
		next unless ($line =~ /\(/);

		next if ($line =~ /^\/|[;]/);

		if ($line =~ /^FN_/) {
			handle_loadparm($file, $line);
		}
		next;
	}

	close(FH);
}


print_header(\&public, $public_define);

process_file(\&public, $_) foreach (@ARGV);
print_footer(\&public, $public_define);

if (not defined($file)) {
	print STDOUT $$public_data;
}

mkpath(dirname($file), 0, 0755);
open(PUBLIC, ">$file") or die("Can't open `$file': $!"); 
print PUBLIC "$$public_data";
close(PUBLIC);
