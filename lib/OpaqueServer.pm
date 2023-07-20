
#!/usr/bin/perl -w


sub main::getEngineInfo {
	OpaqueServer::getEngineInfo(@_);
}

package OpaqueServer;

use strict;
use warnings;


use MIME::Base64 qw(encode_base64 decode_base64);
use Date::Format qw(time2str) ;
use WWSafe;

use LWP::Simple;

use Memory::Usage;

#opaque library
use OpaqueServer::StartReturn;
use OpaqueServer::ProcessReturn;

use OpaqueServer::Resource;
use OpaqueServer::Exception;
use OpaqueServer::Results;
use OpaqueServer::ResultsTMP;
use OpaqueServer::Score;

#pg library
use WeBWorK::PG::Translator;
use WeBWorK::PG::ImageGenerator;
use PGUtil qw(pretty_print not_null);

#webwork2 library
use WeBWorK::Utils::AttemptsTable;
use WeBWorK::Utils::Tasks qw(fake_set fake_problem fake_user);   # may not be needed
use WeBWorK::Localize;
use constant fakeSetName => "Undefined_Set";
use constant fakeUserName => "Undefined_User";


use constant MAX_MARK => 1;

our $memory_usage = Memory::Usage->new();

# debugging configuration defined in conf/opaqueserver.apache-config
our $displayDebuggingData  = $OpaqueServer::Constants::displayDebuggingData;
our $logDebuggingData      = $OpaqueServer::Constants::logDebuggingData;
our $logFile               = $OpaqueServer::Constants::logFile;


####################################################################################
#SOAP CALLABLE FUNCTIONS
####################################################################################



=pod
=begin WSDL
_RETURN $string Hello World!
=cut
sub hello {
    warn "hello world";
    return "hello world!";
}



###############################################################
# new code
###############################################################

our $ce;
our $dbLayout;	
our $db;

# declare a variable for the readonly stance

our $rdonly = 0;

#      * A dummy implementation of the getEngineInfo method.
#      * @return string of XML.

=pod
=begin WSDL
_RETURN     $string    the response below
=end WSDL
=cut

sub getEngineInfo {
		my @in = @_;
        warn "in getEngineInfo with ", @_;
        my $php_version = `php -v`;
        $php_version =~ /^.*$/;
        return '<engineinfo>
                     <Name>Test Opaqueserver engine</Name>
                     <PHPVersion>' . $php_version . '</PHPVersion>
                     <MemoryUsage>' . $memory_usage->report() . '</MemoryUsage>
                     <ActiveSessions>' . 0 . '</ActiveSessions>
                     <working>Yes</working>
                 </engineinfo>';
}

# 
#      * A dummy implementation of the getQuestionMetadata method.
#      * @param string $remoteid the question id
#      * @param string $remoteversion the question version
#      * @param string $questionHint if we show hint
#      * @param string $questionSolution if we show solution
#      * @param string $endingquestionSolution if we show solution after test
#      * @param string $modeExam if question is in exam mode
#      * @param string $questionbaseurl not used
#      * @return string in xml format


=pod
=begin WSDL
_IN questionID             $string
_IN questionVersion        $string
_IN questionHint           $string  questionHint
_IN questionSolution       $string  questionSolution
_IN endingquestionSolution $string  endingquestionSolution
_IN modeExam               $string  modeExam
_IN questionBaseUrl        $string
_FAULT                     OpaqueServer::Exception
_RETURN     		       $string 
=end WSDL
=cut


sub getQuestionMetadata {
	my $self = shift;
	my ($remoteid, $remoteversion, $questionbaseurl, $showhintafter, $showsolutionafter, $showsolutionaftertest, $numattemptlock, $exammode, $questionbaseurl) = @_;
	warn "in getQuestionMetadata";
	warn "\tremoteid $remoteid remoteversion $remoteversion showhintafter $showhintafter showsolutionafter $showsolutionafter showsolutionaftertest $showsolutionaftertest numattemptlock $numattemptlock exammode $exammode questionbaseurl $questionbaseurl";
	$self->handle_special_from_questionid($remoteid, $remoteversion, $showhintafter, $showsolutionafter, $showsolutionaftertest, $numattemptlock, $exammode, 'metadata');
     return '<questionmetadata>
                     <scoring><marks>' . MAX_MARK . '</marks></scoring>
                     <plainmode>no</plainmode>
             </questionmetadata>';


}


# 
#      * A dummy implementation of the start method.
#      *
#      * @param string $questionid question id.
#      * @param string $questionversion question version.
#      * @param string $questionHint if we show hint
#      * @param string $questionSolution if we show solution
#      * @param string $endingquestionSolution if we show solution after test
#      * @param string $maxnumAttempt Num of attempt before read only
#      * @param string $modeExam if question is in exam mode
#      * @param string $url not used.
#      * @param array $paramNames initialParams names.
#      * @param array $paramValues initialParams values.
#      * @param array $cachedResources not used.
#      * @return local_testopaqueqe_start_return see class documentation.

=pod
=begin WSDL
_IN questionID              $string  questionID
_IN questionVersion         $string  questionVersion
_IN questionHint            $string  questionHint
_IN questionSolution        $string  questionSolution
_IN endingquestionSolution  $string  endingquestionSolution
_IN maxnumAttempt           $string  maxnumAttempt
_IN modeExam                $string  modeExam
_IN questionBaseUrl         $string  questionBaseUrl
_IN initialParamNames       @string  paramNames
_IN initialParamValues      @string  paramValues
_IN cachedResources         @string cachedResources
_FAULT               OpaqueServer::Exception 
_RETURN              $OpaqueServer::StartReturn
=end WSDL
=cut

sub start {
    my $self = shift;
	my ($questionid, $questionversion, $questionhint, $questionsolution, $endingquestionsolution, $maxnumattempt, $modeexam, $url, $initialParamNames, $initialParamValues,$cachedResources) = @_;	
	#warn "question base url is $url\n";
	# get course name
	$url = $url//'';
	$url =~ m|.*webwork2/(.*)$|;
	my $courseName = ($1//'')? $1 : 'gage_course';
	
	my $paramNames = ref($initialParamNames)? $initialParamNames:[];
	my $paramValues = ref($initialParamValues)? $initialParamValues:[];
	$self->handle_special_from_questionid($questionid, $questionversion, 'start');
        
	# the above call does nothing for ordinary questions -- does do something for testing questions 
    # zip params into hash
	my $initparams = array_combine($paramNames, $paramValues);
	$initparams->{questionid} = $questionid;
	$initparams->{questionhint} = $questionhint;
	$initparams->{questionsolution} = $questionsolution;
	$initparams->{endingquestionsolution} = $endingquestionsolution;
	$initparams->{maxnumattempt} = $maxnumattempt;
	$initparams->{modeexam} = $modeexam;
	$initparams->{courseName} = $courseName; #store courseName
	
	# use Tim Hunt's magic formula for creating the random seed:
	# _randomseed is the constant 123456789 and attempt is incremented by 1
	# incrementing by more than one helps some pseudo random number generators ????	
	my $problem_seed  = $initparams->{'randomseed'} 
	                     + 12637946 *($initparams->{'attempt'}) || 1;
	$initparams->{computed_problem_seed}= $problem_seed; # update problem_seed.
	
	if ($logDebuggingData) {
		my @lines;
		push @lines, "\n\n##############################\nstart(): \n";
		push @lines, "questionid: $questionid \n";
		push @lines, "#####\nparameters:\n";
		foreach my $key (sort keys %$initparams) {
			my $value = $initparams->{$key};
			push @lines, "$key => $value\n";
		}
		push @lines, "end parameters\n##### \n";
		writeLog(@lines);
		warn "\nparameters for start written to $logFile\n";
	}

	# warn "course used for accessing questions is $courseName\n\n";
	# create startReturn type and fill it
	my $return = OpaqueServer::StartReturn->new(
			$questionid, $questionversion, $initparams->{display_readonly} 
	); #readonly if this value is defined and 1
	
	
	$return->{CSS} = $self->get_css();
	$return->{progressInfo} = "Try 1";
	# $return->{questionSession}=  int(10**5*rand());  
	if (defined($questionid) and $questionid=~/\.pg/i) {
	    #warn "return text of question\n";
	    my $PGscore;
		($return->{XHTML},$PGscore) = $self->get_html($return->{questionSession}, 1, $initparams);
		# need questionid parameter to find source filepath

	} else {
		$return->{XHTML}=$self->get_html_original($return->{questionSession}, 1, $initparams);
	}
	my $resource = OpaqueServer::Resource->make_from_file(
			"$OpaqueServer::RootDir/pix/world.gif", 
			'world.gif', 
			'image/gif'
	);
	$return->addResource($resource);
	   
	######################
	# send data to ww_opaque_server/logs/session.log file
	######################
	if ($logDebuggingData) {
		my @lines = ();
		push @lines, "Return data from start():\n";
		push @lines, "set questionSession =  ",$return->{questionSession},"\n";
		writeLog(@lines);
		warn $return->{questionSession}, " results for start() written to $logFile";
	}

	# return start type
	return $return;
}


# 
#      * returns an object (the structure of the object is taken from an OpenMark question)
#      *
#      * @param $startresultquestionSession
#      * @param $keys
#      * @param $values
#      * @return object

=pod
=begin WSDL
_IN      questionSession  $string
_IN      names            @string
_IN      values           @string 
_FAULT       OpaqueServer::Exception
_RETURN      $OpaqueServer::ProcessReturn
=end WSDL
=cut



sub process {
	my $self = shift;
	my ($questionSession, $names, $values) = @_;
	my $PGscore = 0;
     # zip params into hash
	my $params = array_combine($names, $values);
	# use Tim Hunt's magic formula for creating the random seed:
	# _randomseed is the constant 123456789 and attempt is incremented by 1
	# incrementing by more than one helps some pseudo random number generators ????	
	my $problem_seed  = $params->{'randomseed'} 
	                     + 12637946 *($params->{'attempt'}//0) || 1;
	$params->{computed_problem_seed}= $problem_seed; # update problem_seed.
	
    $self->handle_special_from_process($params);
	# initialize the attempt number and pasttry for showing hint and solution
	$params->{try} = $params->{try}//-666;
	$params->{pasttry} = $params->{pasttry}//0;
	# bump the attempt number if this is a submission
	$params->{try}++ if (defined($params->{WWsubmit}));
	# prepare return object 
	my $return = OpaqueServer::ProcessReturn->new();
	if (defined($params->{questionid} and $params->{questionid}=~/\.pg/i) ){
		($return->{XHTML}, $PGscore) = $self->get_html($questionSession, $params->{try}, $params);
				# need questionid parameter to find source filepath
	} else {
	    # this was used for testing the server using testopaque module
		$return->{XHTML}=$self->get_html_original($questionSession, $params->{try}, $params);
	}
	
	$return->{progressInfo} = 'Try ' .$params->{try};
	$return->addResource( 
		OpaqueServer::Resource->make_from_file(
                "$OpaqueServer::RootDir/pix/world.gif", 
                'world.gif', 
                'image/gif'
        )
		
    );
    
    ##################################
    # Prepare marks
    ##################################
	my $mark = $PGscore;
	my $score;
	$mark = MAX_MARK() if $mark >= MAX_MARK;
	$mark = 0 if $mark <=0;
	$score = OpaqueServer::Score->new($mark);
	
	
    ##################################
    # Return results
    ##################################
   
    if (defined($params->{WWsubmit}) ) {   
    		$return->{resultstmp} = OpaqueServer::ResultsTMP->new();         
            $return->{resultstmp}->{questionLine}  = 'Opaque question: $questionSession';
            $return->{resultstmp}->{answerLine}    = '"finish" command from type issued';
            $return->{resultstmp}->{actionSummary} = 'Finished after ' 
                 . ($params->{'try'} - 1) . ' submits.';
                        $return->{resultstmp}->{attempts} = ($mark)? $params->{try}: -1;
                         push @{$return->{resultstmp}->{scores}}, $score;
            $return->{resultstmp}->{TRY} = $params->{try};
 
    }

    if (defined($params->{finish})){
                $return->{results} = OpaqueServer::Results->new();
            $return->{results}->{questionLine}  = 'Opaque question: $questionSession';
            $return->{results}->{answerLine}    = '"finish" command from type issued';
            $return->{results}->{actionSummary} = 'Finished after '                
                 . ($params->{'try'} - 1) . ' submits.'; 
                        $return->{results}->{attempts} = ($mark)? $params->{try}: -1; 
                        push @{$return->{results}->{scores}}, $score;
         
    }

	if (defined($params->{'-finish'}) ) {
		$return->{questionEnd} = 'true';
		$return->{results} = OpaqueServer::Results->new();
		$return->{results}->{questionLine} = 'Opaque question: $questionSession';
		$return->{results}->{answerLine} = '"-finish" command from behaviour issued';
		$return->{results}->{actionSummary} = 'Finished by Submit all and finish. Treating as a pass.';
		$return->{results}->{attempts} = 0;
                $return->{resultstmp} = OpaqueServer::ResultsTMP->new();
                $return->{resultstmp}->{attempts} = 0;
	}
	
    ##############################################################
    # Push solution and correctans to general feedback if needed #
    ##############################################################
	
	if (defined($params->{body}) && defined($params->{WWsubmit})) {
	    $return->{solfeedback} = $params->{body};
    	}

	
	if (defined($params->{attempttable}) && defined($params->{WWsubmit})){

		$return->{correctanstable} = $params->{attempttable};
	}
	
	##############################################
	# Push attempt table for the attempt history #
	##############################################
	
	if (defined($params->{attempttable1}) && defined($params->{WWsubmit})){
		$return->{correctanstable1} = $params->{attempttable1};
	}

	######################
	# send data to ww_opaque_server/logs/session.log file
	######################
	if ($logDebuggingData) {
		my @lines=();
		my $str = "";
		for my $key (sort keys %$params) {
			$str .= "\t$key => ".$params->{$key}. ", \n";
		}

		push @lines,  "\n##################################################\n";
		push @lines,  "process() with questionSession:  $questionSession\n";
		push @lines,  "\tid = ", $params->{questionid}//'',"\n";
		push @lines,  "\tfinish = ", $params->{finish}//'',"\n";
		push @lines,  "\t-finish = ", $params->{'-finish'}//'', "\n";
		push @lines,  "\tlocalstate, before processing = ", $params->{localstate}//'',"\n";
		push @lines,  "Parameters passed to process ".ref($params)."\n $str\n";
		push @lines,  "##################################################\n";
		########## include results data
		if (ref($return->{resultstmp})=~/HASH/i) {
			my $str = "";
			for my $key (keys %{$return->{resultstmp} }) {
				$str .= "\t$key => ".($return->{resultstmp}->{$key}). ", \n";
			}
			push @lines, "Results returned: \n";
			push @lines, $str;
		}
		writeLog(@lines);
		warn "$questionSession parameters for process() written to $logFile";
	}
	############### end report

	
	$return;
}


=pod
=begin WSDL
_IN questionSession  $string
_FAULT               OpaqueServer::Exception
_RETURN      $OpaqueServer::ProcessReturn

=end WSDL
=cut

sub stop {
	my $self = shift;
	my $questionSession = shift;
	######################
	# send data to ww_opaque_server/logs/session.log file
	######################

	if ($logDebuggingData) {
		my @lines =();
		push @lines, "\nstop(): session: $questionSession\n";
		push @lines,  "additional params: ", join(" ", @_), "\n";
		writeLog(@lines);
		warn "$questionSession parameters for stop() written to $logFile";
	}
	$self->handle_special_from_sessionid($questionSession, 'stop');
}

###########################################
# Utility functions
###########################################

sub array_combine {       # zips two array refs into a hash ref
                          #duplicates a php function -- not a method
        my ($paramNames, $paramValues) = @_;
		my $combinedHash = {};
		my $length = (@$paramNames<@$paramValues)?@$paramValues:@$paramNames;
		return () unless $length==@$paramValues and $length==@$paramNames;
		my @paramValues = (ref($paramValues)=~/array/i)? @$paramValues:();
		my @paramNames  = (ref($paramNames)=~/array/i)? @$paramNames:();
		foreach my $i (1..$length) {
		    my $key = (pop @$paramNames)//$i;
			$combinedHash->{$key}= pop @$paramValues;
		}
		return $combinedHash;
}

# 
#      * Handles actions at the low level.
#      * @param string $code currently 'fail' and 'slow' are recognised
#      * @param string $delay treated as a number of seconds.

sub handle_special {
	my $self = shift;
	my ($code,$delay) = @_;
	warn "handle_special(): with code: $code and delay: $delay\n";
	($code eq 'fail') && do {
		# throw new SoapFault('1', 'Test opaque engine failing on demand.');
		die SOAP::Fault->faultcode(1)->faultstring('Test opaque engine failing on demand.');
	};
	($code eq 'slow') && do {
		# Make sure PHP does not time-out while we sleep.
		# set_time_limit($delay + 10);
		my $timeout = $delay + 10;   #seconds
		my ($buffer, $size, $nread);
		$size =20000;
		eval {  #pulled off web
			local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
			alarm $timeout;
			sleep($delay );  # sleep for delay seconds
			alarm(0);
    	};
		if ($@) {
			die  unless $@ eq "alarm\n";   # propagate unexpected errors
			warn "alarm timed out";
			# timed out
		} else {
			# didn't
		}
        
	};
	# default
	# 		do nothing special

}

#      * Handle any special actions, as determined by the question session id.
#      * @param string $sessionid which will be of the form "$questionid-$version".
#      * @param string $method identifies the calling method.
# 

sub handle_special_from_sessionid {
	my $self = shift;
	my ($sessionid, $method) = @_;
	# handle read-only case
	warn "handle_special_sessionid(): with  session id: $sessionid method: $method \n";
	if (substr($sessionid, 0, 3) eq 'ro-') {
            $sessionid = substr($sessionid, 3);
    }
	if ( $sessionid =~/\-/ ) {	
		my ($questionid, $version) = split('-',$sessionid, 1);		
		$version = $version//'';		
    	$self->handle_special_from_questionid($questionid, $version, $method);
    }
}

# 
#      * Handle any special actions, as determined by the question id.
#      * @param string $questionid questionid. If it start with $method., triggers special actions.
#      * @param string $version question verion. In some cases used as a delay in seconds.
#      * @param string $method identifies the calling method.

sub handle_special_from_questionid {
	my $self = shift;
	my ($questionid, $version, $method) = @_;
	$version = $version//'';   # in case version isn't initialized.
	warn "handle_special_questionid(): $questionid version: $version method: $method\n";
	my $len = length($method) + 1;

	if (substr($questionid, 0, $len) ne ($method . '.')) {
	    warn "handle_special_questionid(): do nothing, this is a regular question\n";
		return; # Nothing special for this method.
	}
	#warn "call handle_special with ",substr($questionid,$len), " $version\n";
    $self->handle_special(substr($questionid, $len), $version);
}

# 
#      * Handle any special actions, as determined by the data sumbitted with a process call.
#      * @param array $params the POST data for this question.

sub handle_special_from_process {
    my $self = shift;
    my ($params) = @_;
	if (defined($params->{fail}) ) {
		$self->handle_special('fail', 0);
	} elsif (defined($params->{slow}) && ( $params->{slow} > 0) ) {
		$self->handle_special('slow', $params->{slow});
	}
}

# 
#      * Generate the HTML we will send back in reply to start/process calls.
#      * @submitteddata array preserved as hidden form fields.
#      * @return string HTML code.
# 

sub get_html {
	my $self = shift;
	my ($sessionid, $try, $submitteddata) = @_; #( submitteddata is the same as initparams )
	
 	# determine whether this session is read only using ro- prefix
	######################################
	my $display_readonly=0;
	if (substr($sessionid, 0, 3) eq 'ro-') {
		$display_readonly = 1;
		$rdonly = 1;
		warn "session id begins with ro- :  $sessionid ";
	}
	
	######################################
	
	my $localstate = $submitteddata->{localstate}//'WWpreview';
	$localstate = 'question_attempted' if $localstate ne 'question_graded' and $submitteddata->{WWsubmit};
	$localstate = 'question_graded'  if $submitteddata->{WWcorrectAns};
	$submitteddata->{localstate}=$localstate; #update $params
	my $WWpreviewDisabled     = ($display_readonly or $localstate eq 'question_graded')?'disabled="disabled" ':'';
	my $WWsubmitDisabled      = ($display_readonly or $localstate eq 'question_graded')?'disabled="disabled" ':'';
	my $WWcorrectAnsDisabled  = ($display_readonly or $localstate eq 'question_graded')?'disabled="disabled" ':'';
	$submitteddata->{finish}='Finish' if $display_readonly or $submitteddata->{WWcorrectAns};
	$submitteddata->{submit}='Submit' if $submitteddata->{WWpreview} or 
	    $submitteddata->{WWsubmit} or $submitteddata->{WWcorrectAns};
	
	######################################
	
	###############################################
	# Force state to be submitted if in exam mode #
	###############################################

	if ($submitteddata->{modeexam} == 1 && $submitteddata->{try} eq "") {
		my $localstate = $submitteddata->{localstate}//'WWpreview';
		$localstate = 'question_attempted';
		$localstate = 'question_graded'  if $submitteddata->{WWcorrectAns};
		$submitteddata->{localstate}=$localstate; #update $params
		my $WWpreviewDisabled     = ($display_readonly or $localstate eq 'question_graded')?'disabled="disabled" ':'';
		my $WWsubmitDisabled      = ($display_readonly or $localstate eq 'question_graded')?'disabled="disabled" ':'';
		my $WWcorrectAnsDisabled  = ($display_readonly or $localstate eq 'question_graded')?'disabled="disabled" ':'';
		$submitteddata->{finish}='Finish' if $display_readonly or $submitteddata->{WWcorrectAns};
		$submitteddata->{submit}='Submit' if $submitteddata->{WWpreview} or 
			$submitteddata->{submit}='Submit';
			$submitteddata->{WWsubmit} = "1";
		
	}
	
	######################################
	# Adjust file path
	######################################
	# the file paths allowed in PG were adjusted to conform to opaque naming requirements
	# this section reconstructs the original PG path
	# - in PG  is replaced by ___ three underscores
	# / in PG  is replaced by -- two underscores
	# an initial Library/... in PG is replaced by library/
	# this implies that using multiple adjacent underscores in a PG file path 
	# is a bad idea.
	#####
	# the opaque standard is 
	#  '[_a-z][_a-zA-Z0-9]*'; -- standard opaque questionid 
	#####
	my $filePath = $submitteddata->{questionid};
	$filePath =~ s/\_\_\_/\-/g;  # hand fact that - is replaced by ___ 3 underscores
	$filePath =~ s/\_\_/\//g; # handle fact that / must be replaced by __ 2 underscores
	$filePath =~ s/^library/Library/;    # handle the fact that id's must start with non-caps (opaque/edit_opaque_form.php)

	###############################################
	# Have PG render the problem for a first time #
	###############################################
	
	my $pg = OpaqueServer::renderOpaquePGProblem($filePath, $submitteddata);

	######################################
	# Calculate the mark (PG score) for the question
	######################################

	my @PGscore_array = map {$_->score} values %{$pg->{answers}};
	my $PGscore=0;
	foreach my $el (@PGscore_array) {
		$PGscore += $el;
	}
	$PGscore = (@PGscore_array) ? $PGscore/@PGscore_array : 0;

    #We add a floor value to only show the correct answer if all the answer of the problem are correct

    my $floor = int($PGscore);
	   
	## if answers are correct automatically bump state to "question_graded"
	## as if the WWcorrectAns button (Finish and Grade) was pushed. Only 
	## apply if not in exam mode
	
	if ($submitteddata->{modeexam} ne 1) {
		if (defined($submitteddata->{WWsubmit}) && $PGscore==1) {
			$submitteddata->{WWcorrectAns} = 1;
			$localstate = 'question_graded'  if $submitteddata->{WWcorrectAns};
			$submitteddata->{localstate}=$localstate;
			$display_readonly = 1;
			$WWpreviewDisabled     = ($localstate eq 'question_graded')?'disabled="disabled" ':'';
			$WWsubmitDisabled      = ($localstate eq 'question_graded')?'disabled="disabled" ':'';
			$WWcorrectAnsDisabled  =  ($localstate eq 'question_graded')?'disabled="disabled" ':'';
		#	$submitteddata->{finish}='Finish' if $display_readonly or $submitteddata->{WWcorrectAns};
			$submitteddata->{submit}='Submit' if $submitteddata->{WWpreview} or 
			$submitteddata->{WWsubmit} or $submitteddata->{WWcorrectAns};
		}
	} 		

    my $answerOrder = $pg->{flags}->{ANSWER_ENTRY_ORDER};
	my $answers = $pg->{answers};
	my $ce = create_course_environment($submitteddata->{courseName});
	
	############################################################################
	# Compare current and past answers to adjust for showing hint and solution #
	############################################################################
		
	my @student_ans;
	my @subcopy;
	my $value1;
	my $key;
	my $count = 0;
	my $diff = 0;
		
	$submitteddata->{answers} = $answers;

	foreach $key (keys %{$submitteddata->{answers}})
    {
        $value1 = $submitteddata->{answers}->{$key}->{'student_ans'};
        push (@student_ans, $value1);
		$count++;
		}
	
	@student_ans = sort @student_ans;
	@student_ans = sort { $a <=> $b } @student_ans;
	
	my $addstr = 'ans1';
	
	for (my $i = 0; $i < $count; $i++) {
		if (defined($submitteddata->{$addstr})){
			$subcopy[$i] = $submitteddata->{$addstr};
			$addstr .= '1';
		}
	}
	
	@subcopy = sort @subcopy;
	@subcopy = sort { $a <=> $b } @subcopy;
	
	for (my $i = 0; $i < $count; $i++) {
            if ($subcopy[$i] eq $student_ans[$i]) {
			    $diff++;
		    
		}
	}
	
	$addstr = 'ans1';
	
    for (my $i = 0; $i < $count; $i++) {
		$submitteddata->{$addstr} = $student_ans[$i];
		$addstr .= '1';
	}
	
	if ($diff == $count){
		$submitteddata->{sameans} = 1;
	} else {
	    $submitteddata->{sameans} = 0;
	}
    
	if ($submitteddata->{try} ne 1 && defined($submitteddata->{WWsubmit})){
        $submitteddata->{pasttry}++ if ($submitteddata->{sameans} eq 1);
	}
	
    my $tryHS;
	if (defined($submitteddata->{pasttry})){
	    $tryHS = ($submitteddata->{try}) - $submitteddata->{pasttry};
	    $submitteddata->{tryHS} = ($submitteddata->{try}) - $submitteddata->{pasttry};
	} else {
		$tryHS = 1;
	    $submitteddata->{tryHS} = 1;
	}
	
	my $Hlimit = $submitteddata->{questionhint};
	my $Slimit = $submitteddata->{questionsolution};
	
	my $Hleft = $submitteddata->{questionhint} - $submitteddata->{tryHS} + 1;
	my $Sleft = $submitteddata->{questionsolution} - $submitteddata->{tryHS} + 1;
	
	#############################################################
	#FIX int in hash key of submitteddate error since PHP 7.4 + #
	#############################################################
	
	#foreach $key (keys %{$submitteddata}){
	#	if ($key =~ /^[+-]?\d+$/ ) {
	#		delete $submitteddata->{0};
	#	}
	#}
	
	############################################
	#Determine if question is at max attempt   #
	############################################
	
	my $step;
	if ($submitteddata->{maxnumattempt} != 0 && $submitteddata->{questionsolution} == 0){
		$step = $submitteddata->{maxnumattempt} - $submitteddata->{tryHS} + 1;
		if ($step <= 0){
			$display_readonly = 1;
		}
	}
	
	
	###############################################
	#Show hint and solution if enough attempt done#
	###############################################
	
	if ($Hlimit ne 0){
		if (($submitteddata->{questionhint} - $submitteddata->{tryHS} + 1) <= 0){
			$submitteddata->{Hshow} = 1;
		} 
		elsif ($Hlimit >=100){
			$submitteddata->{Hshow} = 1;
		}		
		else{
			$submitteddata->{Hshow} = 0;
		}
	}
	
	if ($Slimit ne 0){
		if (($submitteddata->{questionsolution} - $submitteddata->{tryHS} + 1) <= 0){


			$submitteddata->{Sshow} = 1;
		} 
		elsif ($Slimit >=100){
			$submitteddata->{Sshow} = 1;
		}
		else{
			$submitteddata->{Sshow} = 0;
		}
	}
	
	#############################################
	#Push state to readonly if solution is shown#
	#############################################
	
	if (defined($submitteddata->{tryHS})){
	    if(($submitteddata->{questionsolution} ne 0) && ($submitteddata->{tryHS} > $submitteddata->{questionsolution} or $PGscore eq 1)) {		   
		 $display_readonly = 1;
			$submitteddata->{stopall} = 1;
	    }
	}
	
	##########################################################################################
	# if problem is readonly, bump to grade and  "finish state".                             #
    # Useful in Moodle for grading correctly if the test is in "submit all and finish" state.#
	##########################################################################################
	
    if ($display_readonly == 1) {
		$submitteddata->{WWcorrectAns} = 1;
		$localstate = 'question_graded'  if $submitteddata->{WWcorrectAns};
		$submitteddata->{localstate}=$localstate;
        $WWpreviewDisabled     = ($localstate eq 'question_graded')?'disabled="disabled" ':'';
        $WWsubmitDisabled      = ($localstate eq 'question_graded')?'disabled="disabled" ':'';
        $WWcorrectAnsDisabled  =  ($localstate eq 'question_graded')?'disabled="disabled" ':'';
    #    $submitteddata->{finish}='Finish' if $submitteddata->{WWcorrectAns} or $submitteddata->{WWsubmit};
        $submitteddata->{submit}='Submit' if $submitteddata->{WWcorrectAns} or $submitteddata->{WWsubmit};
    }
	
	#############################################
	#Show hint and solution if state is readonly#
	#############################################
	
	if ($localstate eq 'question_graded') {
		$submitteddata->{PGstop} = 1;
	}

    ##################################################################################
    #Ensure that the attempt result is not showed when the "preview" button is pushed#
	#Ensure that attempt result is not showed in exam mode                           #
    ##################################################################################
	
    my $qgraded = '';
    if (($localstate eq 'question_attempted' or $localstate eq 'question_graded') && ($submitteddata->{modeexam} != 1)) {
                $qgraded = 1;
    } else {
                $qgraded = 0;
				$floor = 0;
    }	

    my $tbl = WeBWorK::Utils::AttemptsTable->new(
		$answers//{},
		answersSubmitted       => $submitteddata->{submit},  # a submit button was pressed
		answerOrder            => $answerOrder//[],
		displayMode            => $ce->{pg}->{options}->{displayMode}||'images',
		imgGen                 => '',	
		showAttemptPreviews    => 1,
		showAttemptResults     => $qgraded, #($localstate eq 'question_attempted' or $localstate eq 'question_graded'), 
		showCorrectAnswers     => ($display_readonly or $floor),  #($localstate eq 'question_graded') ,
		showMessages           => 0,
		ce                     => $ce,
		maketext               => WeBWorK::Localize::getLoc("fr_CA"),
	);
	
	if ($submitteddata->{modeexam} == 1) {
		$tbl->{showSummary} = 0;
	}
	
	my $attemptResults = $tbl->answerTemplate();
	# render equation images
	$tbl->imgGen->render(refresh => 1) if $tbl->displayMode eq 'images';	
	
	######################################
	# Store state in HTML page (our implementation of session storage)
	######################################

	#delete $submitteddata->{0};

    my $hiddendata = {
		'try' => $try,
		'questionid' => $submitteddata->{questionid},
		'localstate' => $localstate, 
		%$submitteddata,
	};

           
	#####################################
	## prepare diagonostic information ##
	#####################################

	my $debuggingData = '';
	if ($displayDebuggingData == 1) {
		$debuggingData= join("\n",
			'<h2>WeBWorK-Moodle Question type</h2>',
			'<br/>finish = '.($submitteddata->{'finish'}//''),
			'<br/>-finish= '.($submitteddata->{'-finish'}//''),
			'<br/>display_readonly= '.($submitteddata->{'display_readonly'}//''),
			'<br/>display_correctness= '.($submitteddata->{'display_correctness'}//''),
			"<br/>",
			qq!<p>This is the WeBWorK test Opaque engine at $OpaqueServer::Host <br/>!,
			qq!sessionID: $sessionid with question attempt: $try!, 
			qq!</p>!,
			q!<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js"></script>
			
				<script>
					if (slide_text_div) {
						// alert("Slide_text_div defined");
						// prevent this function from being defined
						// multiple times in one page
					} else {
						var slide_text_div = $(document).ready(function(){
							$( ".clickme" ).click(function() {
							  $( this).next().slideToggle( "slow", function() {
								// Animation complete.
							  });
							});
						   // jQuery methods go here...
						});
					}
				</script>
				<style>
					.clickme {background-color: #ccccFF ;}
				</style>!,
			'<div class="clickme"> Click here to show more details</div>'
		);
		$debuggingData .='<div class="answer-details" style="display: none;">';
		$debuggingData .='
			<h3>Submitted data</h3>
			<table>
			<thead>
			<tr><th>Name</th><th>Value</th></tr>
			</thead>
			<tbody>';

		foreach my $name (keys %$hiddendata)  {
			$debuggingData .= '<tr><th>' . $name . '</th><td>' . 
			htmlspecialchars($hiddendata->{$name}) . "</td></tr>\n";
		}
		$debuggingData .= '
			</tbody>
			</table>';

		$debuggingData .= pretty_print($pg->{answers},'html',4); #  $pg->{body_text};
		$debuggingData .= pretty_print($tbl,'html',4);
		$debuggingData .= '</div>';
	}
	# debugging data prepared
	
    ################################################
	# Have PG render the problem for a second time #
	################################################
	
	$pg = OpaqueServer::renderOpaquePGProblem($filePath, $submitteddata);

	#################################################
	# if readonly, disable input, radio and checkbox#
	#################################################
	
	if ($display_readonly == 1) { 
		my $oldstring = $pg->{body_text};
		my $newstring = $oldstring;
		$newstring =~ s/input/input disabled="disabled"/g;
		$newstring =~ s/INPUT/INPUT disabled="disabled"/ig;
		$newstring =~ s/pg-select"/pg-select" disabled="disabled"/g;
		$pg->{body_text} = $newstring;
	}
	
	#################################################
	# Ensure done => 1 to enable post_filters       #
	#################################################
	
	#my $testdone;
	
	#$submitteddata->{answers} = $answers;
	
	#foreach my $keyt(keys %{$submitteddata->{answers}}){
	#	$testdone .= "$submitteddata->{answers}->{$keyt}\n";
	#}
	
	######################################
	# Prepare output HTML
	######################################
        

    my $output = '<div class="local_testopaqueqe">';
	## store state
	foreach my $name (keys %$hiddendata)  {
		$output .= '<input type="hidden" name="%%IDPREFIX%%' . $name .
				'" value="' . htmlspecialchars($hiddendata->{$name}//'') . '" />' . "\n";
	}

       	## print results table
	if ($submitteddata->{try} ne "") {
		$output .= $attemptResults;
	}
	
	if (not defined($submitteddata->{stopall})){
	
	    ## print number of attempt left before showing hint
	    if ($Hlimit != 0 && $tryHS <= $Hlimit && $PGscore != 1 && $Hlimit < 100){
			if ($Hleft != 1) {
				$output .= '<p> <b> <FONT COLOR="RED"> Il vous reste '. $Hleft .' tentatives avant que les indices soient disponibles. </FONT> </b> </p>';
			}
			else {
				$output .= '<p> <b> <FONT COLOR="RED"> Il vous reste '. $Hleft .' tentative avant que les indices soient disponibles. </FONT> </b> </p>';
			}
	    }		
	
	    ## print number of attempt left before showing solution

        if ($Slimit != 0 && $PGscore != 1 && $Slimit < 100){
			if ($tryHS <= $Slimit){
				if ($Sleft != 1){
					$output .= '<p> <b> <FONT COLOR="RED"> Il vous reste '. $Sleft .' tentatives avant que la question soit verrouill&eacutee. </FONT> </b> </p>';
				} 
				else {
					$output .= '<p> <b> <FONT COLOR="RED"> Il vous reste '. $Sleft .' tentative avant que la question soit verrouill&eacutee. </FONT> </b> </p>';
				}
			}
	    }
	    
		## print number of attempt before question is closed
		
		if ($submitteddata->{maxnumattempt} != 0 && $submitteddata->{questionsolution} == 0 && $PGscore != 1){
			if ($step > 0){
				if ($step != 1){
					$output .= '<p> <b> <FONT COLOR="RED"> Il vous reste '. $step .' tentatives avant que la question soit verrouill&eacutee. </FONT> </b> </p>';
				}
				else {
					$output .= '<p> <b> <FONT COLOR="RED"> Il vous reste '. $step .' tentative avant que la question soit verrouill&eacutee. </FONT> </b> </p>';
				}
			}
		}
	}
	
	## print question text
	$output .= "\n<hr>\n". $pg->{body_text} ."\n<hr>\n";
	
	## print buttons (preview, submit, grade&finish)
	$output .= join("\n",#        '<h4>Actions</h4>',
		'<p>',
	#	q!<button type="submit" name="%%IDPREFIX%%WWpreview"  value=1!.qq!  $WWpreviewDisabled class="btn btn-secondary"> Pr&eacutevisualiser </button> !,	
		q!<button type="submit" name="%%IDPREFIX%%WWsubmit" value=1!.qq!  $WWsubmitDisabled class="btn btn-secondary"> Soumettre </button> !,
	# 	q!<button type="submit" name="%%IDPREFIX%%WWcorrectAns" value=1!.qq!  $WWcorrectAnsDisabled class="btn btn-primary"> Envoyer et Terminer </button>!,
		'</p>',
		'</div>',
	);

	$output .= $debuggingData;
	

    ##################################################
    #Prepare solution for feedback if needed         #
    ##################################################
	
	if ($submitteddata->{endingquestionsolution} == 1){
		if ($Slimit eq 0){
			my $pg2 = OpaqueServer::renderOpaquePGProblemFB($filePath, $submitteddata);
		    $submitteddata->{body} = $pg2->{body_text};
		} 
		elsif (not defined($submitteddata->{stopall})){
			my $pg2 = OpaqueServer::renderOpaquePGProblemFB($filePath, $submitteddata);
		    $submitteddata->{body} = $pg2->{body_text};
		}
		
		else {
		    $submitteddata->{body} = "";
		}
	}
	
	
	
    ######################################################################################
    # Store the attempt table to use in the attempt history when Moodle test is finished #
    ######################################################################################

    $submitteddata->{attempttable1} = $attemptResults;
	
    ##################################################
    #Prepare attempt table for the feedback if needed#
    ##################################################
	
	#if (($submitteddata->{modeexam} == 1) or ($display_readonly != 1)){
		my $tbl2 = WeBWorK::Utils::AttemptsTable->new(
		$answers//{},
		answersSubmitted       => $submitteddata->{submit},  # a submit button was pressed
		answerOrder            => $answerOrder//[],
		displayMode            => $ce->{pg}->{options}->{displayMode}||'images',
		imgGen                 => '',	
		showAttemptPreviews    => 1,
		showAttemptResults     => 1, 
		showCorrectAnswers     => 1,
		showMessages           => 0,
		ce                     => $ce,
		maketext               => WeBWorK::Localize::getLoc("fr_CA"),
		);
		my $attemptResults2 = $tbl2->answerTemplate();
		# render equation images
		$tbl2->imgGen->render(refresh => 1) if $tbl2->displayMode eq 'images';
		
		$submitteddata->{attempttable} = $attemptResults2;
	#} else {
	#	$submitteddata->{attempttable} = "";
	#}
	
#	$output =~ s/-bs-/-/g;
	
	return ($output, $PGscore);

}


##############################################
sub get_html_original {
	my $self = shift;
	my ($sessionid, $try, $submitteddata) = @_;
	my $disabled = '';
	if (substr($sessionid, 0, 3) eq 'ro-') {
		$disabled = 'disabled="disabled" ';
	}

	my $hiddendata = {
		'try' => $try,
	};

    my $output = '
<div class="local_testopaqueqe">
<h2><span>Hello <img src="%%RESOURCES%%/world.gif" alt="world" />!</span></h2>
<p>This is the WeBWorK test Opaque engine  '  ." at $OpaqueServer::Host <br/>  sessionID ".
    $sessionid . ' with question attempt number ' . $try . '</p>';

	foreach my $name (keys %$hiddendata)  {
		$output .= '<input type="hidden" name="%%IDPREFIX%%' . $name .
				'" value="' . htmlspecialchars($hiddendata->{$name}//'') . '" />' . "\n";
	}

        $output .= '
        <h3>Actions</h3>
<p><input type="submit" name="%%IDPREFIX%%submit" value="Submit" ' . $disabled . '/> or
    <input type="submit" name="%%IDPREFIX%%finish" value="Finish" ' . $disabled . '/>
    (with a delay of <input type="text" name="%%IDPREFIX%%slow" value="0.0" size="3" ' .
            $disabled . '/> seconds during processing).
    If finishing assign a mark of <input type="text" name="%%IDPREFIX%%mark" value="' .
            MAX_MARK() . '.00" size="3" ' . $disabled . '/>.</p>
<p><input type="submit" name="%%IDPREFIX%%fail" value="Throw a SOAP fault" ' . $disabled . '/></p>
<h3>Submitted data</h3>
<table>
<thead>
<tr><th>Name</th><th>Value</th></tr>
</thead>
<tbody>';

	foreach my $name (keys %$submitteddata)  {
		$output .= '<tr><th>' . $name . '</td><td>' . 
		htmlspecialchars($submitteddata->{$name}) . "</th></tr>\n";
	}

    $output .= '
</tbody>
</table>
</div>';

        return $output;
    
}

##############################
# Create the course environment $ce and the database object $db
##############################

sub renderOpaquePGProblem {
    
# Get the number of try for enabling hint and solution using $tryHS
# $Hlimit and $Slimit should be pushed from a Moodle form to choose
# the number of attemp before showing the Hint and the Solution 
	
    #print "entering renderOpaquePGProblem\n\n";
    my $problemFile = shift//'';
    my $formFields  = shift//'';  # these fields are part of $submitteddata"
	
	my $Hshow;
    my $Sshow;
	
	my $Hlimit = $formFields->{questionhint};
	my $Slimit = $formFields->{questionsolution};
	
	if ($Hlimit eq 0){
		$Hshow = 0;
	}
	else {
		$Hshow = $formFields->{Hshow};
	}
	
	if ($Slimit eq 0){
		$Sshow = 0;
	}
	else {
		$Sshow = $formFields->{Sshow};
	}
	
	if ($formFields->{PGstop} eq 1) {
		if ($Hlimit ne 0){	
			$Hshow = 1;
		}
		if ($Slimit ne 0){
			$Sshow = 1;
		}
	}
	
    my $courseName = $formFields->{courseName}||'daemon_course';
    #warn "rendering $problemFile in course $courseName \n";
 	$ce = create_course_environment($courseName);
 	$dbLayout = $ce->{dbLayout};	
 	$db = WeBWorK::DB->new($dbLayout);
    #warn "db is $db and ce is $ce \n";
	my $key = '3211234567654321';
	
	my $user          =  fake_user($db); # don't use $formFields->{userid} --it's a number
	my $set           = $formFields->{'this_set'} || fake_set($db);
	# use Tim Hunt's magic formula for creating the random seed:
	# _randomseed is the constant 123456789 and attempt is incremented by 1
	# incrementing by more than one helps some pseudo random number generators ????	
# 	my $problem_seed  = $formFields->{'randomseed'} 
# 	                     + 12637946 *($formFields->{'attempt'}) || 0;
# 	$formFields->{computed_problem_seed}= $problem_seed; # update problem_seed.
        my $problem_seed  = $formFields->{computed_problem_seed};
	my $showHints     = $formFields->{showHints} || $Hshow;
	my $showSolutions = $formFields->{showSolutions} || $Sshow;
	my $problemNumber = $formFields->{'problem_number'} || 1;
       # my $permissionLevel = $formFields->{permissionLevel} || 10;
    my $displayMode   = $ce->{pg}->{options}->{displayMode}//"images";
    #  my $key = $r->param('key');
   
	my $translationOptions = {
		displayMode     => $displayMode,
		showHints       => $showHints,
		showSolutions   => $showSolutions,
        #        permissionLevel => $permissionLevel,
		refreshMath2img => 1,
		processAnswers  => 1,
		QUIZ_PREFIX     => '',	
		use_site_prefix => $ce->{server_root_url},
		use_opaque_prefix => 1,	
	};
	my $extras = {};   # Check what this is used for.
	
	# Create template of problem then add source text or a path to the source file
	 local $ce->{pg}{specialPGEnvironmentVars}{problemPreamble} = {TeX=>'',HTML=>''};
	 local $ce->{pg}{specialPGEnvironmentVars}{problemPostamble} = {TeX=>'',HTML=>''};
	# writeLog("preamble",$ce->{pg}{specialPGEnvironmentVars}{problemPreamble}{HTML});
	my $problem = fake_problem($db, 'problem_seed'=>$problem_seed);
	$problem->{value} = -1;	
	#warn "problem->problem_seed() ", $problem->problem_seed, "\n";
	if (ref $problemFile) {
			$problem->source_file('');
			$translationOptions->{r_source} = $problemFile; # a text string containing the problem
	} else {
			$problem->source_file($problemFile); # a path to the problem
	}
	
	#FIXME temporary hack
	$set->set_id('this set') unless $set->set_id();
	$problem->problem_id("1") unless $problem->problem_id();
		
		
	my $pg = new WeBWorK::PG(
		$ce,
		$user,
		$key,
		$set,
		$problem,
		123, # PSVN (practically unused in PG)
		$formFields,
		$translationOptions,
		$extras,
	);
		return $pg;
}

##############################
# Create the second rendering for de general feedback
##############################

sub renderOpaquePGProblemFB {
    
	
    #print "entering renderOpaquePGProblemFB\n\n";
    my $problemFile = shift//'';
    my $formFields  = shift//'';  # these fields are part of $submitteddata"
    my $courseName = $formFields->{courseName}||'daemon_course';
    #warn "rendering $problemFile in course $courseName \n";
 	$ce = create_course_environment($courseName);
 	$dbLayout = $ce->{dbLayout};	
 	$db = WeBWorK::DB->new($dbLayout);
    #warn "db is $db and ce is $ce \n";
	my $key = '3211234567654321';
	
	my $user          =  fake_user($db); # don't use $formFields->{userid} --it's a number
	my $set           = $formFields->{'this_set'} || fake_set($db);
	# use Tim Hunt's magic formula for creating the random seed:
	# _randomseed is the constant 123456789 and attempt is incremented by 1
	# incrementing by more than one helps some pseudo random number generators ????	
# 	my $problem_seed  = $formFields->{'randomseed'} 
# 	                     + 12637946 *($formFields->{'attempt'}) || 0;
# 	$formFields->{computed_problem_seed}= $problem_seed; # update problem_seed.
        my $problem_seed  = $formFields->{computed_problem_seed};
	my $showHints     = $formFields->{showHints} || 0;
	my $showSolutions = $formFields->{showSolutions} || 1;
	my $problemNumber = $formFields->{'problem_number'} || 1;
       # my $permissionLevel = $formFields->{permissionLevel} || 10;
    my $displayMode   = $ce->{pg}->{options}->{displayMode}//"images";
    #  my $key = $r->param('key');
   
	my $translationOptions = {
		displayMode     => $displayMode,
		showHints       => $showHints,
		showSolutions   => $showSolutions,
		refreshMath2img => 1,
		processAnswers  => 1,
		QUIZ_PREFIX     => '',	
		use_site_prefix => $ce->{server_root_url},
		use_opaque_prefix => 1,	
	};
	my $extras = {};   # Check what this is used for.
	
	# Create template of problem then add source text or a path to the source file
	# local $ce->{pg}{specialPGEnvironmentVars}{problemPreamble} = {TeX=>'',HTML=>''};
	# local $ce->{pg}{specialPGEnvironmentVars}{problemPostamble} = {TeX=>'',HTML=>''};
	# writeLog("preamble",$ce->{pg}{specialPGEnvironmentVars}{problemPreamble}{HTML});
	my $problem = fake_problem($db, 'problem_seed'=>$problem_seed);
	$problem->{value} = -1;	
	#warn "problem->problem_seed() ", $problem->problem_seed, "\n";
	if (ref $problemFile) {
			$problem->source_file('');
			$translationOptions->{r_source} = $problemFile; # a text string containing the problem
	} else {
			$problem->source_file($problemFile); # a path to the problem
	}
	
	#FIXME temporary hack
	$set->set_id('this set') unless $set->set_id();
	$problem->problem_id("1") unless $problem->problem_id();
		
		
	my $pg2 = new WeBWorK::PG(
		$ce,
		$user,
		$key,
		$set,
		$problem,
		123, # PSVN (practically unused in PG)
		$formFields,
		$translationOptions,
		$extras,
	);
		return $pg2;
}

####################################################################################
# Create_course_environment -- utility function
# requires webwork_dir
# requires courseName to keep warning messages from being reported
# Remaining inputs are required for most use cases of $ce but not for all of them.
####################################################################################


sub create_course_environment {
	my $courseName = shift;
	my $ce = WeBWorK::CourseEnvironment->new( 
				{webwork_dir		=>		$OpaqueServer::RootWebwork2Dir, 
				 courseName         =>      $courseName,
				 webworkURL         =>      $OpaqueServer::RPCURL,
				 pg_dir             =>      $OpaqueServer::RootPGDir,
				 });
	warn "Unable to find environment for course: |$OpaqueServer::courseName|" unless ref($ce);
	return ($ce);
}

####################################################################################

#########################################################
# Logging
#########################################################

sub writeLog {
	my @message = @_;
	local *LOG;
	if (open LOG, ">>", $logFile) {
		print LOG "[", time2str("%a %b %d %H:%M:%S %Y", time), "] @message\n";
		close LOG;
	} else {
		warn "failed to open $logFile for writing: $!";
	}
}

# 
#     * Get the CSS that we use in our return values.
#     * @return string CSS code.
# 
sub get_css {
	my $self = shift;
    return <<END_CSS;
		.que.opaque .formulation .local_testopaqueqe {
			border-radius: 5px 5px 5px 5px;
		/*	background: #E4F1FA; */
			padding: 0.5em;

		}
		.local_testopaqueqe h2 {
			margin: 0 0 10px;
		}
		.local_testopaqueqe h2 span {
			background: black;
			border-radius: 5px 5px 5px 5px;
			padding: 0 10px;
			line-height: 60px;
			font-size: 50px;
			font-weight: bold;
			color: #CCBB88;
		}
		.local_testopaqueqe h2 span img {
			vertical-align: bottom;
		}
		.local_testopaqueqe table th {
			text-align: left;
			padding: 0 0.5em 0 0;
		}
		.local_testopaqueqe table td {
			padding: 0 0.5em 0 0;
		}
		/* styles for the attemptResults table */
		table.attemptResults {
			border-collapse: separate;
			border: 1px solid rgba(0,0,0,.200);
            border-radius: 0.25rem;
			background-color: #fdfdfe;
		/*      removed float stuff because none of the other elements nearby are
				floated and it was causing trouble
			float:left;
			clear:right; */
		}

		table.attemptResults td,
		table.attemptResults th {
			border-style: inset;
            border: 1px solid rgba(0,0,0,.200);
            padding: 0.75rem;						
			text-align: center; 
			vertical-align: middle;
			color: #000000;
		}

		.attemptResults .popover {
			max-width: 100%;
		}

		table.attemptResults td.FeedbackMessage { background-color:#EDE275;} /* Harvest Gold */
		table.attemptResults td.ResultsWithoutError { background-color:#8F8;}
		span.ResultsWithErrorInResultsTable { color: inherit; background-color: inherit; } /* used to override the older red on white span */ 
		table.attemptResults td.ResultsWithError { background-color:#D69191; color: #000000} /* red */

END_CSS
}
sub htmlspecialchars {
	return shift;
}
1;
