#!/usr/bin/perl -w

##### DESCRIPTION ######################################################
# genfs2.pl Will generate an arbitrarily complex/deep
# filesystem consisting of random directories and files.
#
# Because filenames and contents are random, you can run the utility
# multiple times over the same directory to increase the density. While
# there is always the chance of a collision, overwriting a random file
# with another of the same name, this risk should be acceptable given
# the potential number of files you're interested in generating.
########################################################################

##### MODULES ##########################################################
use strict;
use Getopt::Std;
########################################################################

##### LOREM IPSUM ######################################################
my @lorem=qw/
	lorem ipsum dolor sit amet consectetur adipiscing elit aenean 
	rhoncus urna at sapien laoreet ac bibendum ipsum semper proin 
	vestibulum ligula in est scelerisque lobortis sit amet id ipsum 
	cras sit amet dictum sem aliquam erat volutpat nulla facilisi 
	donec aliquet nisl ac euismod lacinia nisl elit consectetur l
	eo vitae venenatis mi leo quis eros nullam sapien odio faucibus 
	quis hendrerit eu posuere a tellus nullam laoreet libero vel 
	tortor vestibulum vel tincidunt leo commodo ut magna orci 
	condimentum in eleifend ac facilisis sed mauris proin felis 
	magna ornare sit amet scelerisque eget bibendum ullamcorper 
	ante duis vel sapien nisi sed id leo at metus rutrum bibendum 
	vel et justo duis vehicula laoreet velit vel dignissim magna 
	tristique viverra nulla vitae purus nec risus fringilla interdum 
	et a urna donec rutrum aliquam purus facilisis posuere purus 
	adipiscing adipiscing aliquam erat volutpat nam et leo metus donec 
	et nisl lectus nam nec urna tortor praesent ac massa nisi praesent 
	lacinia ullamcorper est ac fermentum proin dolor sem bibendum in 
	tempus quis iaculis tempus sem vestibulum hendrerit augue ut erat 
	auctor nec lacinia metus bibendum sed est neque volutpat ac porta 
	et aliquet sed justo sed non purus sapien suspendisse erat enim 
	rhoncus dapibus tincidunt nec pulvinar quis mauris pellentesque 
	habitant morbi tristique senectus et netus et malesuada fames ac 
	turpis egestas praesent eu nisl eget metus ultricies varius 
	consectetur at nibh vestibulum non libero ac odio condimentum 
	fringilla sed nec nibh praesent nec massa nec erat
	/;
########################################################################

my $maxFiles = 0;
my $fileCount = 0;
my $minDirsPerLayer = 5;
my $maxDirsPerLayer = 10;
my $minFilesPerLayer = 5;
my $maxFilesPerLayer = 10;
my $minRecurse = 5;
my $maxRecurse = 10;
my $targetDir = "not supplied";
my $minFileSize = 1024;
my $maxFileSize = 1048576;
my $dataChunkSize = 52428800;
my $minFileNameLength = 5;
my $maxFileNameLength = 15;
my $compressableFiles = 0;
my $minimumPermittedFileSize = 511;
my $chunkSize = 8192;
my $segSize = 512;
my $verbose = 0;
my $tmp;
my $realFileNames = 0;
my @chars=("a","b","c","d","e","f","g","h","i","j","k","l","m","n","o",
		   "p","q","r","s","t","u","v","w","x","y","z","_","@","=","+",
		   "A","B","C","D","E","F","G","H","I","J","K","L","M","N","O",
		   "P","Q","R","S","T","U","V","W","X","Y","Z","1","2","3","4",
		   "5","6","7","8","9","0");
my $charLength = @chars+0;
my $randomChars;
my @extensions = (".ppt",".doc",".docx",".txt",".dat",".idx",".anr",".bsb",
	 ".xls",".xlm",".xlt",".docm",".zip",".tar",".tgz",".tbz2",".tar.bz2",
	 ".tar.gz",".rar",".mp3",".mov",".wma",".wmv",".dot",".zap",".7r",".hqx",
	 ".spa",".gba");
my $extLength = @extensions+0;
my $currentYear = (localtime(time))[5]-100;	# Shrink to YY.
my %opts;


##############################################################################
# Subroutines
##############################################################################

# in_mib($bytes) returns the size of a given number in MiB.
sub in_mib {
	if (@_+0 != 1) {
		die "Unexpected input for in_mib(bytes)\n";
	}
	
	# else...
	my $bytes = $_[0];
	if (defined($bytes)) {
		return $bytes / 1024 / 1024;
	} else {
		die "in_mib: Got null bytes.\n";
	}
}

# get_options() retrieves the options and borks if necessary.
sub get_options {
	if (getopts('d:D:f:F:r:R:t:s:S:l:L:M:P:hCNv',\%opts)) {
		usage() if (defined($opts{h}));
		$verbose = 1 if (defined($opts{v}));
		if (defined($opts{M})) {
			if ($opts{M} =~ /^\d+$/) {
				$maxFiles = $opts{M};
			}
		}
		if (defined($opts{d})) {
			if ($opts{d} < 1) {
				die "$opts{d} is too small for minimum number of directories.\n";
			} else {
				$minDirsPerLayer = $opts{d};
			}
		}
		if (defined($opts{N})) {
			$realFileNames = 1;
		}
		if (defined($opts{D})) {
			if ($opts{D} < $minDirsPerLayer) {
				die "Max dirs per layer must be larger than min dirs per layer.\n";
			} else {
				$maxDirsPerLayer = $opts{D};
			}
		} 
		if (defined($opts{f})) {
			if ($opts{f} < 1) {
				die "$opts{f} is too small for minimum number of files.\n";
			} else {
				$minFilesPerLayer = $opts{f};
			}
		}
		if (defined($opts{F})) {
			if ($opts{F} < $minFilesPerLayer) {
				die "Max files per layer must be larger than min files per layer.\n";
			} else {
				$maxFilesPerLayer = $opts{F};
			}
		} 
		if (defined($opts{r})) {
			if ($opts{r} < 1) {
				die "Minimum recursion depth is 1.\n";
			} else {
				$minRecurse = $opts{r};
			}
		}
		if (defined($opts{R})) {
			if ($opts{R} < $minRecurse) {
				die "Maximum recursion depth must be deeper than minimum recursion depth.\n";
			} else {
				$maxRecurse = $opts{R};
			}
		}
		if (defined($opts{t})) {
			if (-d $opts{t}) {
				$targetDir = $opts{t};
			} else {
				die "Specified target directory $opts{t} does not exist!\n";
			}
		} else {
			die "Target directory must be specified (and exist)\n";
		}
		if (defined($opts{s})) {
			if ($opts{s} < $minimumPermittedFileSize) {
				die "Minimum file size must be at least $minimumPermittedFileSize bytes.\n";
			} else {
				$minFileSize = $opts{s};
			}
		}
		if (defined($opts{S})) {
			if ($opts{S} < $minFileSize) {
				die "Maximum filesize must be larger than minimum filesize.\n";
			} else {
				$maxFileSize = $opts{S};
			}
		}
		if (defined($opts{l})) {
			if ($opts{l} < 2) {
				die "The minimum filename length must be >= 2.\n";
			} else {
				if (defined($opts{N})) {
					warn("Semi-realistic filenames (-N) requested. Min filename length will be ignored.");
				}
				$minFileNameLength = $opts{l};
			}
		}
		if (defined($opts{L})) {
			if ($opts{L} < $minFileNameLength) {
				die "The maximum filename length must be greater than the minimum filename length.\n";
			} else {
				if (defined($opts{N})) {
					warn("Semi-realistic filenames (-N) requested. Max filename length will be ignored.");
				}
				$maxFileNameLength = $opts{L};
			}
		}
		if (defined($opts{C})) {
			$compressableFiles = 1;
		}
		if (defined($opts{P})) {
			$dataChunkSize = $opts{P};
		}
	} else {
		die "Many options were not present (fix this error message)\n";
	}
}

# terminate_max_files() lets the user know that we terminated because we hit
# the maximum file count.
sub terminate_max_files {
	# Maybe in a future version we'll report how much we had created here.
	# For now, just terminate.
	die "\n*** Reached $maxFiles files. Terminating.\n";
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

	# else...
	my $segsPerChunk = int($chunkSize / $segSize);
	my $i;
	my $dataSize = length($randomChars);
	my $start;

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
		}
		close(FILE);
		return 1;
	} else {
		return 0;
	}
}


# generate_files($dir,$isStart) generates a random number of files within 
# the given bounds ($minFilesPerLayer -> $maxFilesPerLayer)
# Returns the number of files generated, or 0 if there's an error.
sub generate_files {
	my ($dir,$isStart) = @_[0,1];
	return 0 if (! -d $dir);

	my $numFiles = int(rand($maxFilesPerLayer - $minFilesPerLayer)) + $minFilesPerLayer;
	if ($isStart || $verbose) {
		print "($numFiles).\n";
	}
	my $count;
	my $fileSize = 0;
	if ($realFileNames) {
		for ($count = 0; $count < $numFiles; $count++) {
			my $filename = rand_name_realistic("f");
			$fileSize = int(rand($maxFileSize-$minFileSize))+$minFileSize;
			randfile($fileSize,"$dir/$filename");
			$fileCount++;
			if ($fileCount % 100000 == 0) {
				print "\t\t$fileCount files\n";
			}
			if ($fileCount > $maxFiles && $maxFiles != 0) {
				terminate_max_files();
			}
		}
	} else {
		for ($count=0; $count<$numFiles; $count++) {
			my $filename = rand_name_standard($minFileNameLength,$maxFileNameLength);
			# Now, since this is a filename, quickly work out whether we 
			# should attach an extension to the file.
			my $extensionRequired = int(rand(6));
			if ($extensionRequired != 0) {
				my $extension = $extensions[(int(rand(@extensions+0)))];
				$filename .= $extension;
			}
			$fileSize = int(rand($maxFileSize-$minFileSize))+$minFileSize;
			randfile($fileSize,"$dir/$filename");
			$fileCount++;
			if ($fileCount % 100000 == 0) {
				print "\t\t$fileCount files\n";
			}
			if ($fileCount > $maxFiles && $maxFiles != 0) {
				terminate_max_files();
			}
		}
	}
}

# generate_subdirs($min,$max) generates a list of subdirectory names -
# with a minimum of $min and a maximum of $max.
sub generate_subdirs {
	my ($min, $max) = @_;
	my $numDirs = int(rand($max-$min))+$min;
	my $count;
	my @subDirList;
	if ($realFileNames) {
		for ($count=0; $count<$numDirs; $count++) {
			push(@subDirList,rand_name_realistic("d"));
		}
	} else {
		for ($count=0; $count<$numDirs; $count++) {
			push(@subDirList,rand_name_standard($minFileNameLength,$maxFileNameLength));
		}
	}
	return @subDirList;
}

# populate_subdir($dirName,$recurseDepth) populates a given 
# $dirName (creating it) with files and subdirectories to a maximum
# depth of $recurseDepth.
sub populate_subdir {
	my ($dirName,$recurseDepth) = @_;
	# TODO: Add error checking here.
	mkdir($dirName,0775);
	print "\tGenerating files for $dirName. " if ($verbose);
	generate_files($dirName,0);
	return 1 if ($recurseDepth == 0);

	# else...
	my @subDirs=generate_subdirs($minDirsPerLayer,$maxDirsPerLayer);
	my $subDir;
	foreach $subDir (@subDirs) {
		my $subRecurseDepth = int(rand($recurseDepth-1));
		print "\tWill populate $dirName/$subDir to max depth $subRecurseDepth\n" if ($verbose);
		populate_subdir("$dirName/$subDir",$subRecurseDepth);
	}
}

# rand_name_standard($min,$max) generates a random filename at least $min
# chars long and at most $max chars long. If the "realFileNames" flag
# is turned on the min/max details are ignored.
sub rand_name_standard {
	my ($min,$max) = @_;
	my $charListLength = @chars+0;
	my $length = int(rand($max-$min))+$min;
	my $filename = "";
	my $count;
	for ($count = 0; $count<$length; $count++) {
		$filename .= $chars[int(rand($charListLength))];
	}
	return $filename;
}

# rand_name_realistic({f|d}) generates a random filename that looks a little
# more realistic. (Just a little).
sub rand_name_realistic {
	if (@_+0 != 1) {
		die "random_name: Received unexpected options (should be just 1)\n";
	}
	
	# else...
	my $type = $_[0];
	my $nameType = "";
	if (lc($type) =~ /^f/) {
		$nameType = "file";
	} elsif (lc($type) =~ /^d/) {
		$nameType = "directory";
	} else {
		die "random_name: Should have got 'f' or 'd' as an argument. Got '$type'.\n";
	}
	my $maxWordLength = ($nameType eq "d") ? int(rand(2))+1 : int(rand(4))+1;
	my $fileName = "";
	
	my $numEntries = @lorem+0;
	for (my $count = 1; $count <= $maxWordLength; $count++) {
		$fileName .= $lorem[int(rand($numEntries))];
		if ($nameType eq "file") {
			# Toss a coin.
			my $extraBit = int(rand(15));
			if ($extraBit <= 11) {
				$fileName .= "-" . $chars[int(rand($charLength))];
				if ($count != $maxWordLength) {
					$fileName .= "-";
				}
			}
		} else {
			# Toss a slightly different coin.
			my $extraBit = int(rand(5));
			if ($extraBit < 2) {
				$fileName .= "-" . sprintf("%02d",int(rand($currentYear)));
				if ($count != $maxWordLength) {
					$fileName .= "-";
				}
			}
		}
	}
	
	# once done, if filename, then check to see if we should add an extension.
	if ($nameType eq "file") {
		# Toss a coin.
		if (int(rand(100)) > 3) {
			$fileName .= $extensions[int(rand($extLength))];
		}
	}
	
	return $fileName;
}


# pre_generate($size) pre-generates an array containing random chars
# to a maximum of $size bytes. The array is assumed to be @randomChars
# because we don't want to be passing say, a 500MiB an array backwards
# and forwards
sub pre_generate {
	my $size = $_[0];
	my $count;
	my $max = ($compressableFiles == 0) ? 255 : 97;
	my $number;
	my $lastPercent = -1;
	$size += ($segSize*2);	# Give ourselves a bit of buffer.
	for ($count = 1; $count <= $size; $count++) {
		$randomChars .= chr(int(rand($max)));
		$number = int($count / $size * 100);
		if ($number % 10 == 0) {
			print "\t\t$number% of random data chunk generated.\n" if ($lastPercent != $number);
			$lastPercent = $number;
		}
	}
}


# usage() gives usage information and exits.
sub usage {
	die "Syntax: $0 [-d minDir] [-D maxDir] [-f minFile] [-F maxFile] [-r minRecurse] [-R maxRecurse] -t target [-s minSize] [-S maxSize] [-l minLength] [-L maxLength] [-C] [-P dCsize] [-N] [-v] [-M maxFiles]\n

Creates a randomly populated filesystem for backup/recovery and general
performance testing. Files created are typically non-compressable.

All options other than target are optional. Values in parantheses beside
explanations denote defaults that are used if not supplied.

Where:

	-d minDir\tMinimum number of directories per layer. (5)
	-D maxDir\tMaximum number of directories per layer. (10)
	-f minFile\tMinimum number of files per layer. (5)
	-F maxFile\tMaximum number of files per layer. (10)
	-r minRecurse\tMinimum recursion depth for base directories. (5)
	-R maxRecurse\tMaximum recursion depth for base directories. (10)
	-t target\tTarget where directories are to start being created.
	\t\tTarget must already exist. This option MUST be supplied.
	-s minSize\tMinimum file size (in bytes). (1 K)
	-S maxSize\tMaximum file size (in bytes). (1 MB)
	-l minLength\tMinimum filename/dirname length. (5)
	-L maxLength\tMaximum filename/dirname length. (15)
	-P dCsize\tPre-generate random data-chunk at least dcSize bytes.
	\t\tWill default to $dataChunkSize bytes.
	-M maxFiles\tMaximum number of files to generate. (Only files are
		counted, directories are not.)
	-N \t\tTry to generate pseudo-realistic looking filenames.
	-C \t\tTry to provide compressable files.
	-v \t\tBe verbose.

E.g.:

$0 -r 2 -R 32 -s 512 -S 65536 -t /d/06/test

Would generate a random filesystem starting in /d/06/test, with a minimum
recursion depth of 2 and a maximum recursion depth of 32, with a minimum
filesize of 512 bytes and a maximum filesize of 64K.

Tips: 

1. For ultra-dense filesystems, reduce file-size min/max as you increase
   number of directories and recursion.
2. Due to random filenames/directory names being produced, instead of
   trying to get 'perfect' results first go, simply re-run the utility
   on the same target point multiple times as needed.\n\n";
}

# dump_settings() dumps the current settings to screen.
sub dump_settings {
	# Now, generate dump of settings.
	print <<EOF;
Configured with the following settings:
	Min dirs per layer = $minDirsPerLayer
	Max dirs per layer = $maxDirsPerLayer
	Min files per layer = $minFilesPerLayer
	Max files per layer = $maxFilesPerLayer
	Target directory = $targetDir
	Min file size = $minFileSize
EOF
	if ($maxFileSize >= 1048576) {
		print "\tMax file size = " . sprintf("%0.1f",in_mib($maxFileSize)) . " MB\n";
	} else {
		print "\tMax file size = $maxFileSize\n";
	}
	print "\tMin recursion depth = $minRecurse\n";
	print "\tMax recursion depth = $maxRecurse\n";
	if (!$realFileNames) {
		print "\tMin filename length = $minFileNameLength\n";
		print "\tMax filename length = $maxFileNameLength\n";
	} else {
		print "\tUse realistic filenames = yes\n";
	}
	print "\tTry for compressable files = $compressableFiles\n";
	print "\tMaximum files = ";
	if ($maxFiles == 0) {
		print "(unbound)\n";
	} else {
		print "$maxFiles\n";
	}

	print "\tPre-generate a datachunk size = " . in_mib($dataChunkSize) . "MB\n";
	print "\n";
}


##############################################################################
# Main
##############################################################################

get_options();

# Die if we don't have a target directory specified. Everything else 
# is optional/ has defaults assigned to it.
die "Target directory (-t) not specified\n" if ($targetDir eq "not supplied");

# Else, go ahead.
dump_settings();
print "Progress:\n";
print "\tPre-generating random data chunk. (This may take a while.)\n";
pre_generate($dataChunkSize);


# Start doing the work.
print "\tGenerating files in root directory of $targetDir. ";
generate_files($targetDir,1);
my @subDirList = generate_subdirs($minDirsPerLayer,$maxDirsPerLayer);
my $numSubDirs = @subDirList+0;
my $subDirCount = ($numSubDirs == 1) ? "1 subdirectory" : "$numSubDirs subdirectories";
print "\t$subDirCount to generate.\n";
#my $subDir;
#foreach $subDir (@subDirList) {
for (my $subDirI = 0; $subDirI < $numSubDirs; $subDirI++) {
	my $subDir = $subDirList[$subDirI];
	my $recurseLength = int(rand($maxRecurse-$minRecurse))+$minRecurse;
	print "\t(" . ($subDirI+1) . "/$numSubDirs) New subdirectory $subDir - max recurse depth $recurseLength\n";
	populate_subdir("$targetDir/$subDir",$recurseLength);
}

print "\tTotal number of files created: $fileCount\n";
