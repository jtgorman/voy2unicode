#!/usr/bin/env perl

use strict ;
use warnings ;

# an experment to see if I can
# read in a utf-8 marc file
# normalize the utf-8 fields,
# and then save out as a marc record with the correct number of
# bytes in leader/directory

# use -l MARC

# subclass if necessary

use Unicode::Normalize ;
use MARC::Record ;
use MARC::File::USMARC ;

#note, this is different form checking
#whether a string is internally utf
# for that, use utf8; utf8::is_utf8( $string ) ;
# 
#use Unicode::CheckUTF8 qw(is_utf8);

my $marc_file = $ARGV[0] ? $ARGV[0] : 'Miserables.bib' ;

my $file = MARC::File::USMARC->in( $marc_file ) ;

open my $outfile, '>>:utf8',  'Miserables_nfc_utf8.mrc' or die "Couldn't open file $! \n" ;

RECORD: while ( my $marc = $file->next() ) {

    # if a record says it's not in utf-8, just skip

    # we might want to make sure the file is
    # really utf8 by doing something like CheckUTF8
    if($marc->encoding ne 'UTF-8') {
        next RECORD ;
    }

    # not sure if this is the best way to do this...

    FIELD: foreach my $field ($marc->fields()) {
        # either a control field or a data field

        # if control, pretty sure there's nothing to normalize
        # and no subfields to iterate over
        if($field->is_control_field()) {
            next FIELD ;
        }
        # if data, update ...
        else {

            # get normalized subfields
            my @subfields = () ;

            foreach my $subfield ($field->subfields()) {
                my $code = $subfield->[0] ;
                my $data = NFC( $subfield->[1] ) ;
                
                #print "At subfield $code, value $data \n" ;
                
                push(@subfields, $code, $data ) ;
            }

            # update only replaces first occurrance of subfield, need replace
            # which isn't that much harder
            $field->replace_with(
                MARC::Field->new(
                    $field->tag(),
                    $field->indicator(1),
                    $field->indicator(2),
                    @subfields,
                )
              );
        }
    }
    
    # technically this isn't correct, we
    # should be putting these records into a batch
    # object, as if I remember correctly there's separators
    # look at later...

    print $outfile $marc->as_usmarc() ;

}

