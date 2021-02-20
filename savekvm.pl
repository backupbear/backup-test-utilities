#!/usr/bin/perl -w

############################################################################
# backup-kvm.pl
# 
# Example script for backing up KVM virtual machines to NetWorker
#
# Author: Preston de Guise, https://nsrd.info/blog
#
# For usage examples, see the following blog posts:
#
# General introduction:
# https://nsrd.info/blog/2018/11/06/a-simple-linux-kvm-backup-framework-using-networker/
#
# Updated for 'clustered' support:
# https://nsrd.info/blog/2019/02/08/updated-kvm-image-backup-script-for-networker/
#
# ====================== DISCLAIMER ========================================
# USE THIS SCRIPT AT YOUR OWN RISK
# AUTHOR TAKES NO RESPONSIBILITY FOR THE RUNNING OF THIS SCRIPT
# YOU SHOULD ALWAYS VERIFY SUCCESSFUL BACKUP AND RECOVERY OPERATIONS
# ====================== DISCLAIMER ========================================
#
############################################################################

############################################################################
# Modules
############################################################################
use File::Basename;
use Sys::Hostname;
use Getopt::Std;


############################################################################
# Globals
############################################################################
my $self = basename($0);
my $host = hostname();
my $shortHost = $host;
   $shortHost =~ s/^([^\.]*)\..*/$1/;
my $runningOnly = 1;
my $virsh = "/usr/bin/virsh";
my $version = "1.3";
my $clustClient = "";
my $saveCommandVM = "save -LL -q -s #server# #cluster# -b #pool# -e #retention# -N #shortHost#:KVM:#guest#:#disk# #path#";
my $saveCommandConfig = "save -LL -q -s #server# #cluster# -b #pool# -e #retention# -N #shortHost#:KVM:#guest#:config #path#";
my $tmpDir = "/tmp";
my $runCommands = 1;
my $snapPrefix = "nsr_";
my $log = "/nsr/applogs/savekvm.log";
my $retention = 31;
my $pool = "Default";
my $debug = 0;
my $server = $host;
my $quiesce = "";


############################################################################
# Subroutines
############################################################################

# fail(@messages) prints whatever messages are given then exits with a return code
# of 1, indicating unsuccessful execution.
sub fail {
	if (@_+0 > 0) {
		my @messages = @_;
		foreach my $message (@messages) {
			my $tmp = $message;
			chomp $tmp;
			print "$tmp\n";
		}
	}
	exit(1);
}

# write_log(@messages) writes the given messages to the log file.
sub write_log {
	if (@_+0 != 0) {
		my @messages = @_;
		if (open(LOG,">>$log")) {
			foreach my $message (@messages) {
				my $tmp = $message;
				chomp $tmp;
				print LOG "$tmp\n";
			}
			close(LOG);
		} else {
			# Soft warn here.
			warn("Asked to write to $log but unable to.\n");
			return 0;
		}
	} else {
		return 1;
	}
}

# usage([@text]) gives standard usage information, any additional messages sent through
# then exits.
sub usage {
	print <<EOF;
Usage: $self [-h] [-v] [-n] [-r days] [-b pool] [-s nsr] [-c host [-Q]

Where:
	-h	Prints help and exits.
	-v	Prints version and exits.
	-n	Displays steps that would be performed without performing them.
	-Q	Invoke snapshots with quiesce option (requires guest agent).
	-r days	Retention to use, in days (integer only). Default: $retention
	-b pool	Pool to use. Default: $pool
	-s nsr	NetWorker server to use. Default: $server
	-c host	Use specified host as client name (for clustered hypervisors).

Coordinates snapshots of KVM guests running on Linux and performs backup
directly to NetWorker.
EOF

	if (@_+0 > 0) {
		foreach my $line (@_) {
			my $tmp = $line;
			chomp $tmp;
			print "$tmp\n";
		}
	}
	log_end();
	exit(0);
}

# pre_check() confirms we're running a hypervisor that is compatible with live
# snapshots and reintegration.
sub pre_check() {
	my $hyperOK = 0;
	my $APIOK = 0;
	
	# Might need to adjust this to suit API more than Hypervisor version - will need
	# to do some additional research here.
	if (open(CMD,"$virsh version |")) {
		while (<CMD>) {

			my $line = $_;
			chomp $line;
			if ($line =~ /Running hypervisor: QEMU (\d+).*$/i) {
				my $major = $1;
				if ($major >= 2) {
					$hyperOK = 1;
				}
				write_log("Found hypervisor version: $major");
			}
			if ($line =~ /^Using API: QEMU (\d+).*/) {
				my $major = $1;
				if ($major >= 3) {
					$APIOK = 1;
				}
				write_log("Found API version: $major");
			}
		}
		close(CMD);
		
		if ($hyperOK && $APIOK) {
			write_log("Hypervisor & API versions check out.");
			return 1;
		} else {
			write_log("Unexpected/unsuppored Hypervisor and/or API version.");
			return 0;		}
	} else {
		write_log("Could not run $virsh version");
		fail("Unable to run pre-check via $virsh version.");
	}
}

# get_options() checks for command line options and adjusts flags/settings
# accordingly.
sub get_options {
	my %opts = ();
	if (getopts('hvnr:b:s:Qc:',\%opts)) {
		usage() if (defined($opts{'h'}));
		die "$self is v$version\n" if (defined($opts{'v'}));
		$runCommands = 0 if (defined($opts{'n'}));
		if (defined($opts{Q})) {
			$quiesce = "--quiesce";
			write_log("User has requested snapshot quiesce option");
		} else {
			write_log("Snapshots will not be quiesced");
		}
		if (defined($opts{c})) {
			$clustClient = $opts{c};
			write_log("User has specified cluster client: $clustClient");
		} else {
			write_log("No cluster client specified, using current host.");
		}
		if (defined($opts{s})) {
			$server = $opts{s};
			write_log("User has requested server $server");
		} else {
			write_log("Will default to server $server");
		}
		if (defined($opts{b})) {
			$pool = $opts{b};
			write_log("User has requested pool $pool");
		} else {
			write_log("Will default to pool $pool");
		}
		if (defined($opts{r})) {
			if ($opts{r} =~ /^\d+$/) {
				$retention = $opts{r};
				write_log("User has requested retention: $retention days");
			} else {
				write_log("Invalid retention specified: $retention");
				usage("Invalid retention specified: '$retention' (expecting integer only)");
			}
		} else {
			write_log("Will default to retention: $retention days");
		}
	} else {
		write_log("Unable to get command line options, unsafe to continue.");
		fail("Unable to get command line options, unsafe to continue.");
	}
}

# get_vms() returns a list of VMs we need to protect. If the runningOnly flag is
# set to 1, we only return VMs that are in the 'running' state.
sub get_vms {
	my @vms = ();
	if (open(CMD,"$virsh list 2>&1 |")) {
		while (<CMD>) {
			my $line = $_;
			chomp $line;
			next if ($line =~ /\s*Id\s*Name\s*State/);
			next if ($line =~ /^------/);
			next if ($line =~ /^\s*$/);
			# else...
			$line =~ s/^\s+(.*)/$1/;
			my ($id,$name,$state) = (split(/\s+/,$line))[0,1,2];
			if ($runningOnly) {
				if ($state eq "running") {
					push(@vms,$name);
				}
			} else {
				push(@vms,$name);
			}
		}
		write_log("","Found Virtual Machine(s): " . join(", ",@vms),"");
		return(@vms);
	} else {
		write_log("Error: UNable to execute $virsh list");
		fail("Error: unable to execute $virsh list");
	}
}

# perform_backup(virtMachine,snapName) performs a backup of the given virtual machine.
sub perform_backup {
	if (@_+0 != 2) {
		die "perform_backup(virtMachine,snapName) called with unexpected number of arguments\n";
	}

	# else...
	my $virtualMachine = $_[0];
	my $snapshotName = $_[1];
	my %disks = ();

	write_log("Take backup of $virtualMachine with snap name $snapshotName");
	# Find out what disks we need to take a snapshot of.
	if (open(VIRSH,"virsh domblklist $virtualMachine --details|")) {
		while (<VIRSH>) {
			my $line = $_;
			chomp $line;
			if ($line =~ /^file\s+disk\s+(vd.)\s*(.*)/) {
				$disks{$1} = $2;
				write_log("$virtualMachine: Found disk $1 at $2");
			}
		}
		if (close(VIRSH)) {
			write_log("virsh domblklist exited successfully.");
		} else {
			write_log("virsh domblklist exited unsuccessfully."); 
		}
	} else {
		write_log("$virtualMachine: Could not retrieve disk information");
		fail("Could not retrieve disk information...");
	}
	
	# Take the snapshot
	my $snapCommand = "virsh snapshot-create-as --domain $virtualMachine --name $snapshotName --no-metadata $quiesce --atomic --disk-only";
	foreach my $disk (sort {lc $a cmp lc $b} keys %disks) {
		$snapCommand .= " --diskspec $disk,file=$disks{$disk}.$snapshotName,snapshot=external";
	}
	write_log($snapCommand);
	$debug && print "DEBUG>> Snapshot: $snapCommand\n";
	if ($runCommands) {
		if (open(SNAP,"$snapCommand 2>&1 |")) {
			my $createdMessage = 0;
			my @output = ();
			while (<SNAP>) {
				my $line = $_;
				chomp $line;
				push(@output,$line);
				if ($line =~ /^\s*Domain snapshot $snapshotName created/) {
					$createdMessage = 1;
				}
			}
			if (close(SNAP)) {
				write_log("Snapshot command exited successfully.");
			} else {
				write_log("Snapshot command exited unsuccessfully.");
				fail("Snapshot command exited unsuccessfully.");
			}
			write_log("Take snapshot:",@output);
			if ($createdMessage) {
				write_log("Snapshot appears to have been taken successfully, proceed with backup.");
			} else {
				write_log("Snapshot was possibly not taken successfully. Unsafe to proceed.");
				fail("Snapshot was possibly not taken successfully. Unsafe to proceed.");
			}
		} else {
			write_log ("Snapshot returned with unexpected error code. Unsafe to continue.");
			fail ("Snapshot returned with unexpected error code. Unsafe to continue.");
		}
	} else {
		write_log("Mode: Do not run commands. Snapshot not executed.");
	}
	
	# Now, perform the backup.
	foreach my $disk (sort {lc $a cmp lc $b} keys %disks) {
		my $cmdVM = $saveCommandVM;
		$cmdVM =~ s/\#guest\#/$virtualMachine/g;
		if ($clustClient !~ /^$/) {
			$cmdVM =~ s/\#host\#/$clustClient/g;
			$cmdVM =~ s/\#shortHost\#/$clustClient/g;
		} else {
			$cmdVM =~ s/\#host\#/$host/g;
			$cmdVM =~ s/\#shortHost\#/$shortHost/g;
		}
		$cmdVM =~ s/\#disk\#/$disk/g;
		$cmdVM =~ s/\#path\#/$disks{$disk}/g;
		$cmdVM =~ s/\#pool\#/$pool/g;
		$cmdVM =~ s/\#retention\#/"+$retention days"/g;
		$cmdVM =~ s/\#server\#/$server/g;
		if ($clustClient !~ /^$/) {
			$cmdVM =~ s/\#cluster\#/-c $clustClient/g;
		} else {
			$cmdVM =~ s/\#cluster\#//g;
		}
		$debug && print "DEBUG>> $cmdVM\n";
		write_log("Run backup with command: $cmdVM");
		if ($runCommands) {
			if (open(SAVE,"$cmdVM 2>&1 |")) {
				my @saveOutput = ();
				while (<SAVE>) {
					my $line = $_;
					chomp $line;
					push(@saveOutput,$line);
				}
				if (close(SAVE)) {
					write_log("Save successful:",@saveOutput);	
				} else {
					write_log("Save unsuccessful:",@saveOutput);
				}
			} else {
				write_log("Failed to run $cmdVM");
				fail("Failed to run $cmdVM");
			}
		} else {
			write_log("Mode: Do not run commands. Backup not executed.");
		}
	}
	
	# Release the Kraken! I mean snapshot.
	foreach my $disk (sort {lc $a cmp lc $b} keys %disks) {
		# When we run this command, look for the output "Successfully pivoted"
		my $cmd = "virsh blockcommit $virtualMachine $disks{$disk}.$snapshotName --active --pivot";
		$debug && print "DEBUG>> $cmd\n";
		if ($runCommands) {
			if (open(COMMIT,"$cmd 2>&1 |")) {
				my @output = ();
				while (<COMMIT>) {
					my $line = $_;
					chomp ($line);
					push(@output,$line);
				}
				close(COMMIT);
				write_log("Snapshot release:", @output);
			} else {
				write_log("Failed to run $cmd");
				fail("Failed to run $cmd");
			}
		} else {
			write_log("Mode: Do not run commands. Snapshot not released.");
		}
		
		$debug && print "DEBUG>> rm $disks{$disk}.$snapshotName\n";
		if ($runCommands) {
			write_log("Delete snapshot: $disks{$disk}.$snapshotName");
			system("rm $disks{$disk}.$snapshotName");
			if (-f $disks{$disk}.$snapshotName) {
				write_log("Delete snapshot: Failed to remove $disks{$disk}.$snapshotName");
				# Design: Keep going here and keep trying to release other snapshots.
			} else {
				write_log("Delete snapshot: Snapshot file deleted");
			}
		} else {
			write_log("Mode: Do not run commands. No snapshot file to delete.");
		}
	}
	
	# Now dump the config file.
	my $dumpConfigPath = "$tmpDir/$virtualMachine.xml";
	my $dumpConfig = "virsh dumpxml $virtualMachine > $dumpConfigPath";
	$debug && print "DEBUG>> $dumpConfig\n";
	if ($runCommands) {
		system($dumpConfig);
		if (-f $dumpConfigPath) {
			write_log("Generated configuration dump file at $dumpConfigPath");
		} else {
			write_log("Failed to generate configuration dump file: $dumpConfigPath");
			fail("Failed to generate configuration dump file: $dumpConfigPath");
		}
	} else {
		write_log("Mode: Do not run commands. No configuration dump file generated.");
	}
	
	# Now, backup the config file.
	my $backupCommand = $saveCommandConfig;
	$backupCommand =~ s/\#guest\#/$virtualMachine/g;
	if ($clustClient !~ /^$/) {
		$backupCommand =~ s/\#host\#/$clustClient/g;
		$backupCommand =~ s/\#shortHost\#/$clustClient/g;
	} else {
		$backupCommand =~ s/\#host\#/$host/g;
		$backupCommand =~ s/\#shortHost\#/$shortHost/g;
	}
	$backupCommand =~ s/\#path\#/$dumpConfigPath/g;
	$backupCommand =~ s/\#pool\#/$pool/g;
	$backupCommand =~ s/\#retention\#/"+$retention days"/g;
	$backupCommand =~ s/\#server\#/$server/g;
	if ($clustClient !~ /^$/) {
		$backupCommand =~ s/\#cluster\#/-c $clustClient/g;
	} else {
		$backupCommand =~ s/\#cluster\#//g;
	}
	$debug && print "DEBUG>> $backupCommand\n";
	
	if ($runCommands) {
		if (open(SAVE,"$backupCommand 2>&1 |")) {
			my @output = ();
			while (<SAVE>) {
				my $line = $_;
				chomp $line;
				push(@output,$line);
			}
			if (close(SAVE)) {
				write_log("Configuration dump save:",@output);
			} else {
				write_log("Unsuccessful configuration dump save:",@output);
				fail("Unsuccessful configuration dump save:",@output);
			}
		} else {
			write_log("Failed to save configuration dump");
			fail("Failed to save configuration dump");
		}
	}
	
	$debug && print "DEBUG>> rm $dumpConfigPath\n";
	if ($runCommands) {
		system("rm $dumpConfigPath");
		if (-f $dumpConfigPath) {
			write_log("Failed to delete configuration dump $dumpConfigPath");
			# Keep going anyway.
		} else {
			write_log("Deleted configuration dump $dumpConfigPath");
		}
		return 1;
	} else {
		write_log("Mode: Do not run commands. No configuration dump to backup.");
		return 1;
	}

	# Fall through - if we hit here, something weird has happened so return 0.
	write_log("Fallen through to an unexpected exit");
	return 0;
}

# get_timestamp() returns a timestamp for us to use in the snapshot name.
sub get_timestamp {
	my ($second,$minute,$hour,$day,$month,$year) = (localtime(time))[0,1,2,3,4,5];
	$month++;
	$year+=1900;
	$second = sprintf("%02d",$second);
	$minute = sprintf("%02d",$minute);
	$hour = sprintf("%02d",$hour);
	$day = sprintf("%02d",$day);
	$month = sprintf("%02d",$month);
	
	my $timestamp = "$year$month$day$hour$minute$second";
	return $timestamp;
}


# log_start() is invoked at the start of a run to log the date/time we've started
sub log_start {
	my $timestamp = get_timestamp;
	if (open(LOG,">>$log")) {
		print LOG "=" x 70 . "\n";
		print LOG $self . " executed by " . $ENV{LOGNAME} . " at $timestamp on $host\n";
		print LOG "\n";
		print LOG "Command Line Arguments: " . join(" ",@ARGV) . "\n";
		print LOG "=" x 70 . "\n";
		close(LOG);
	} else {
		fail("Could not write to $log");
	}
}

# log_end() is invoked at the end of a run to log the date/time we've finished.
sub log_end {
	my $timestamp = get_timestamp;
	if (open(LOG,">>$log")) {
		print LOG "=" x 70 . "\n";
		print LOG "Ended at $timestamp\n";
		print LOG "=" x 70 . "\n\n\n";
		close(LOG);
	} else {
		fail("Could not write to $log");
	}
}

############################################################################
# Main
############################################################################

log_start();
if (!pre_check()) {
	die "Unable to confirm we are running a recent enough hypervisor.\n";
}
get_options();
my @virtMachines = get_vms();
foreach my $virtMachine (@virtMachines) {
	print "Will backup $virtMachine\n";
	print "\tDetails will be appended to $log\n";
	my $snapName = $snapPrefix . get_timestamp();
	if (perform_backup($virtMachine,$snapName)) {
		print "Backup of $virtMachine completed\n";
	} else {
		# TODO Log an error message and stop here.
	}
}
log_end();
