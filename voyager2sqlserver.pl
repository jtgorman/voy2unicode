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
        
    open my $ucs2_out, '>:raw', 'test_ucs2.txt' or die "Could not open test_usc2.txt: $!\n";

    open my $utf8_out, '>:utf8', 'test_utf8.txt' or die "Could not open test_usc2.txt: $!\n";
    
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
    my $utf8_title ;
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

    
    my $norm_nfd_title = NFD( $utf8_title ) ;
    print $utf8_out "NFD form " . $norm_nfd_title . " \n" ;
    print "NFD form (using NFD from Unicode::Normalize): \n" . unpack("H*",$norm_nfd_title) . "\n\n" ;


    my $norm_kd_title = NFKD( $utf8_title ) ;
    print $utf8_out "ND form " . $norm_kd_title . " \n" ;
    print "ND form (using NFKD from Unicode::Normalize): \n" . unpack("H*",$norm_kd_title) . "\n\n" ;

    my $norm_kc_title = NFKC( $utf8_title ) ;
    print $utf8_out "KC form " . $norm_kc_title . " \n" ;
    print "KC form (using NFKC from Unicode::Normalize): \n" . unpack("H*",$norm_kc_title) . "\n\n" ;

    # write out to the filehandle (which is in raw binmode)
    # the UCS-2LE encoding of the nfc normalized title
    #
    # This is the format that is used by SQL Server
    
    print $ucs2_out encode('UCS-2LE', $norm_nfc_title) ;
    


    # store in the database - see if valid...

    my $mssqlDb = setUpMSSQLDb( %config ) ;
    storeInDatabase( $mssqlDb ,
                     $bib_id,
                     $norm_nfc_title ) ;

    # comment out following section if no google db 
    
    
    
}



sub storeInDatabase {

    my $mssqlDb = shift ;
    my $bib_id   = shift ;
    my $title    = shift ;


    print "Debugging, passed in title $title \n";
    
    my $insert_h = $mssqlDb->prepare( 'insert into title_test (bib_id,title) values (?,?)');

    #  trying to use the encoded_title leads to weird errors and a truncated string
    #my $encoded_title = encode('UCS-2LE', $title);
    #print "Debugging, encoded_title $encoded_title \n";


    # it appears the driver assumes utf-8 and converts it to the proper
    # encoding for nvarchar fields in SQL Server
    #
    # if you try to insert a UCS-2LE encoded string, it only
    # stores the first character.
    
    
    $insert_h->execute( $bib_id, $title ) ;
    
    
    my $title_hex_in_mssql_q = 'select convert(varbinary(4000),title) as RAWHEX from title_test where bib_id = ?' ;  

    my $title_hex_in_mssql_h = $mssqlDb->prepare( $title_hex_in_mssql_q ) ;

    $title_hex_in_mssql_h->execute( $bib_id ) ;

    while(my $mssql_row_ref = $title_hex_in_mssql_h->fetchrow_hashref()) {
        print "RAWHEX in mssql table: " . $mssql_row_ref->{RAWHEX} . "\n" ;

    }
    
    #$mssqlDb->commit() ;
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


sub setUpMSSQLDb {

    my %_config = @_ ;
    
    my $mssql_driver   = $_config{'GoogleDBdriver'};
    my $mssql_server   = $_config{'GoogleDBserver'};
    my $mssql_database = $_config{'GoogleDB'};

    my $mssql_dsn = "dbi:ODBC:Driver=${mssql_driver};Server=${mssql_server};database=${mssql_database};";
    
    # I'm using SQL Server's trusted connection
    # for this particular test database
    my $mssql_dbh = DBI->connect($mssql_dsn, 
                                 undef,
                                 undef,
                                 {
                                     #AutoCommit => 0,
                                     ShowErrorStatement => 1,
                                     HandleError => \&handleDbError,
                                 });
    if (!$mssql_dbh) {
        die("Could not connect to $mssql_dsn, $DBI::errstr $! $@");
    }
    elsif ($mssql_dbh->err) {
        die("Could not connect to $mssql_dsn: $mssql_dbh->errstr $! $@");
    }
    return $mssql_dbh;
}


