#!/usr/bin/env perl

use strict ;
use warnings ;

use Config::General ;

use DBI ;

use Unicode::Normalize;

use Encode qw(encode decode) ;



run() ;

sub run {


    # could probably use :encoding('UCS-2LE') and
    # not even bother with the raw/then UCS-2LE
        
    open my $utf8_out, '>:utf8', 'test_nfc_utf8.txt' or die "Could not open test_nfc_utf8.txt: $!\n";
    
    my $configFile = 'db.conf';



    my $configObject = new Config::General(
        -ConfigFile      => $configFile,
        -InterPolateVars => 1,
    );

    my %config = $configObject->getall();

    my $voyagerDb = setUpVoyagerDb( %config ) ;

    my $get_title_q = 'select TITLE from uiudb.bib_text where bib_id = ?';
    my $get_title_h = $voyagerDb->prepare( $get_title_q ) ;


    my $get_raw_title_q = 'select rawtohex(TITLE) AS RAWTITLE from uiudb.bib_text where bib_id = ?';
    my $get_raw_title_h = $voyagerDb->prepare( $get_raw_title_q ) ;

    #at some point might

    # This is a record we have for Les Miserables with
    # a combining diacritic for the e (u+0065 followed by U+0301)
    my $bib_id = '450479' ;

    print "Pulling record for $bib_id\n";

    $get_title_h->execute( $bib_id ) ;

    my $title ;
    while (my $row_ref = $get_title_h->fetchrow_hashref()) {

    
        $title = $row_ref->{TITLE} ;
        print "Title: $title \n" ; 
    
    }

    my $raw_title ;
    $get_raw_title_h->execute( $bib_id ) ;
    while (my $row_ref = $get_raw_title_h->fetchrow_hashref() ) {
        # show the hextoraw
        $raw_title = lc($row_ref->{RAWTITLE}) ;
        print "Raw hex of title: \n${raw_title} \n\n" ;
    }


    # converts to perl's internal encoding, typically utf-8
    # but definitely seems to need this step to have nfc work as expected
    my $utf8_title = decode("utf8", $title) ;


    # note that some of the terminal prints below
    # seem to get funky, I suspect due to a combination
    # of not specifying the right encoding on STDOUT
    # and my terminal (cygwin). it's generally clsoe.

    
    # show via unpack
    print "Raw hex stored in perl before any decoding or encoding: \n" . unpack("H*",$title) . "\n\n" ;

    
    # use normalization and show internal vai unpack

    # One of the steps in the transformation w/ nfc
    # is substituting combining diacritics with
    # precomposed characters
    #
    # So U+0065 followed by U+0301 (utf-8 hex:65cc81)  will become
    #    U+00E9                    (utf-8 hex:c3a9)
    my $norm_nfc_title = NFC( $utf8_title ) ;
    print $utf8_out "NFC form " . $norm_nfc_title . " \n" ;
    
    print "NFC form (using NFC from Unicode::Normalize): \n" . unpack("H*",$norm_nfc_title) . "\n\n" ;

}

sub setUpVoyagerDb {

    my %config = @_ ;

    
    my $voydsn = "dbi:ODBC:Driver=$config{'VoyDriver'};DBQ=$config{'VoyDBQ'};uid=$config{'VoyUser'};pwd=$config{'VoyPass'}";
    
    my $voyagerDb = DBI->connect( $voydsn, 
                                  undef,
                                  undef,
                                  {
                                      ShowErrorStatement => 1,
                                      HandleError => \&handleDbError 
                                  }
			      ) || die "Can't execute statement: $DBI::errstr";
    
    return $voyagerDb;
}

sub handleDbError {
	
    my $errorMesg   = shift;
    my $dbHandle    = shift;
    my $returnValue = shift;
    
    print "Database error: $!";
    print "Database error: $returnValue, $errorMesg \n";

}

