#!/usr/bin/perl -w

# genbf2.pl - attempt to generate a big, random file that doesn't yield
# much in the way of space savings to conmpression or deduplication.
#
# Example execution: genbf2.pl -s 10240 -f bigfile.dat
#     bigfile.dat 10737418240 bytes 
# 								--> bzip2
# bigfile.dat.bz2 10656877342 bytes
# 
# Originally written by Preston de Guise (twitter:@backupbear)

use strict;
use Getopt::Std;

my $dataChunkSize = 10485760;
my $randomChars = "";
my $filename = "";
my $sizeMiB = 50;
my $size = $sizeMiB * 1024 * 1024;
my %opts;

##############################################################################
# Subroutines
##############################################################################

# usage() shows usage information, any other supplied messages, then exits.
sub usage {
	print <<EOF;
Usage: generate-big-file.pl [-h] [-c size] -s size -f filename

Generates a big random file.

-h		Print this help and exit.
-c size		Randomized seed size, in MiB (default is $sizeMiB MiB, suitable for most files.)
-s size		File size in MiB, default is $sizeMiB MiB.
-f filename	File to write to.

EOF

	if (@_+0 != 0) {
		foreach my $message (@_) {
			my $tmp = $message;
			chomp($tmp);
			print "$tmp\n";
		}
	}
	exit(0);
}

# randfile($size,$filename) generates a random file from $randomChars using
# $chunkSize and $segSize to more quickly generate it.
sub randfile {
	my ($size,$filename) = @_;
	if (-f $filename) {
		return 0;
	}
	if ($size < 1) {
		return 0;
	}
	my $currSize = 0;
	my $chunkSize = $dataChunkSize / 50;
	my $segSize = $chunkSize / 100;

	# else...
	my $segsPerChunk = int($chunkSize / $segSize);
	my $i;
	my $dataSize = length($randomChars);
	my $start;

	my $count = 0;
	if (open(FILE,">$filename")) {
		while ($currSize < $size) {
			my $chunk = "";
			for ($i = 0; $i < $segsPerChunk; $i++) {
				$start = int(rand($dataSize));
				$chunk .= substr($randomChars,$start,$segSize);
			}
			if (length($chunk) > ($size-$currSize)) {
				$chunk = substr($chunk,0,$size-$currSize);
			}
			syswrite(FILE,$chunk);
			$currSize += length($chunk);
			$count++;
		}
		close(FILE);
		print "Wrote data file in $count chunks.\n";
		return 1;
	} else {
		return 0;
	}
}

# pre_generate($size) pre-generates a string containing random
# characters to a maximum of $size bytes. This is held in the global
# $randomChars.
sub pre_generate {
	my $size = $_[0];
	my $count;
	my $max = 255;
	my $number;
	my $lastPercent = -1;
	my $segSize = $dataChunkSize / 10 / 50;
	$size += ($segSize*2);	# Give ourselves a bit of buffer.
	for ($count = 1; $count <= $size; $count++) {
		$randomChars .= chr(int(rand($max)));
		$number = int($count / $size * 100);
		if ($number % 10 == 0 && $lastPercent ne $number) {
			print "\t\t$number% of random data chunk generated.\n";
			$lastPercent = $number;
		}
	}
}

##############################################################################
# Main
##############################################################################

# Read command line options.
if (getopts('hc:f:s:',\%opts)) {
	usage() if (defined($opts{h}));
	if (defined($opts{c})) {
		if ($opts{c} =~ /^\d+$/) {
			$dataChunkSize = $opts{c} * 1024 * 1024;
		}
	}
	if (defined($opts{f})) {
		$filename = $opts{f};
	} else {
		usage("You must supply a filename to write to - '-f filename'");
	}

	if (defined($opts{s}) && $opts{s} =~ /^\d+$/) {
		$size = $opts{s} * 1024 * 1024;
		$sizeMiB = $opts{s};
	}
}

print "Progress:\n";
print "\tPre-generating random data chunk.\n";
pre_generate($dataChunkSize);

print "\tCreating $sizeMiB MiB file $filename from pre-generated random data.\n";
randfile($size,$filename);
