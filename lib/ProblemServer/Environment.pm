package ProblemServer::Environment;

use strict;
use warnings;
use Safe;
use Opcode qw(empty_opset);

BEGIN { $main::VERSION = "2.3.2"; }

sub new {
    my ($self,$path,$host,$pgroot,$wsdl,$rpc,$psfileurl) = @_;
    my $safe = Safe->new;

    # Compile the "include" function with all opcodes available.
        my $include = q[ sub include {
		my ($file) = @_;
		my $fullPath = "].$path.q[/$file";
		# This regex matches any string that begins with "../",
		# ends with "/..", contains "/../", or is "..".
		if ($fullPath =~ m!(?:^|/)\.\.(?:/|$)!) {
			die "Included file $file has potentially insecure path: contains \"..\"";
		} else {
			local @INC = ();
			my $result = do $fullPath;
			if ($!) {
				warn "Failed to read include file $fullPath (has it been created from the corresponding .dist file?): $!";
			} elsif ($@) {
				warn "Failed to compile include file $fullPath: $@";
			} elsif (not $result) {
				warn "Include file $fullPath did not return a true value.";
			}
		}
	} ];

    my $maskBackup = $safe->mask;
    $safe->mask(empty_opset);
    $safe->reval($include);
    $@ and die "Failed to reval include subroutine: $@";
    $safe->mask($maskBackup);

    #Cant seem to pass variables into global.conf since its safe, so hack
    my $preps = '$problemServer{host} = "' . $host . '";' .
        ' $problemServer{wsdl} = "' . $host  . $wsdl .'";' .
        ' $problemServer{rpc}  = "' . $host  . $rpc . '";' .
        ' $pg_dir              = "' . $pgroot . '";' .
        ' $problemserver_url_files = "' . $psfileurl . '";' .
        ' $problemServerDirs{root} = "' . $path . '";';
    #die $preps;
    #$safe->reval($preps);
    my $globalEnvironmentFile = "$path/conf/global.conf";
    my $globalFileContents = readFile($globalEnvironmentFile);

    $globalFileContents =~ s/MARKER_FOR_APACHE_CONF/$preps/;
    #die $globalFileContents;
    #$globalFileContents = $preps.'\n'.$globalFileContents;
    $safe->reval($globalFileContents);

    $@ and die "Could not evaluate global environment file $globalEnvironmentFile: $@";

    no strict 'refs';
    my %symbolHash = %{$safe->root."::"};
    use strict 'refs';

    # convert the symbol hash into a hash of regular variables.
    $self = {};
    foreach my $name (keys %symbolHash) {
	# weed out internal symbols
	next if $name =~ /^(INC|_.*|__ANON__|main::)$/;
	# pull scalar, array, and hash values for this symbol
	my $scalar = ${*{$symbolHash{$name}}};
	my @array = @{*{$symbolHash{$name}}};
	my %hash = %{*{$symbolHash{$name}}};
	# for multiple variables sharing a symbol, scalar takes precedence
	# over array, which takes precedence over hash.
	if (defined $scalar) {
	    $self->{$name} = $scalar;
	} elsif (@array) {
            $self->{$name} = \@array;
	} elsif (%hash) {
            $self->{$name} = \%hash;
	}
    }
    bless $self;
    return $self;

}

sub readFile($) {
	my $fileName = shift;
	local $/ = undef; # slurp the whole thing into one string
	open my $dh, "<", $fileName
		or die "failed to read file $fileName: $!";
	my $result = <$dh>;
	close $dh;
	return force_eoln($result);
}

sub force_eoln($) {
	my ($string) = @_;
	$string =~ s/\015\012?/\012/g;
	return $string;
}

1;
