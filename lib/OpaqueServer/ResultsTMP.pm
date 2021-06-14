package OpaqueServer::ResultsTMP;

=pod
=begin WSDL
        _ATTR questionLine         $string summary of question
        _ATTR answerLine           $string summary of answer        	
        _ATTR actionSummary        $string  summary of action    
        _ATTR attempts             $string   (integer)
        _ATTR scores               @OpaqueServer::Score  compoundObject
        _ATTR customResults        @OpaqueServer::CustomResult compoundObject
        _ATTR TRY                  $string   (integer)

=end WSDL
=cut
sub new {
    my $self;
    my $data;
    $self->{questionLine}       = "";
    $self->{answerLine}     	= "";
    $self->{actionSummary}   	= "";
    $self->{attempts}     		= ""; 
    $self->{scores}   			= [];
    $self->{customResults}     	= []; 
    $self->{TRY}                = "";

    bless $self;
    return $self;
}

1;
