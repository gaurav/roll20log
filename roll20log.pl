#!env perl

use v5.010;

use strict;
use warnings;

use Try::Tiny;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;

use MIME::Base64;
use JSON;

# Prepare STDOUT for extreme UTF-8-ness.
binmode(STDOUT, ":encoding(utf-8)");

# Process command-line arguments so we know what we're doing.
my $help;
my $man;

my $flag_hide_metadata = 0;
my $flag_script_mode = 0;

GetOptions(
    'help|?' => \$help, 
    man => \$man,

    'hide-metadata' => \$flag_hide_metadata,
    'script-mode' => \$flag_script_mode
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;

# Assume any files still on the path are .html files that need parsing.
my @all_messages;

foreach my $filename (@ARGV) {
    try {
        say STDERR "Reading HTML file '$filename'.";

        open(my $fh, "<:encoding(utf-8)", $filename) 
            or die "  Could not open '$filename': $!";

        my $msgdata;
        while(<$fh>) {
            chomp;

            if(/^\s*var msgdata = "([\w\+\/]+)";\s*$/) {
                die "  Two msgdata lines in one file, what?" if defined $msgdata;
                $msgdata = $1;
            }
        }

        close($fh);

        die "  No msgdata line found in file!" unless defined $msgdata; 

        say STDERR "  msgdata of " . length($msgdata) . " characters found.";

        my $json_source = MIME::Base64::decode_base64($msgdata);
        my $json = JSON::decode_json($json_source);

        # This is broken up into chunks for some reason. Hmm.
        my $chunk_id = 0;
        foreach my $chunk (@$json) {
            $chunk_id++;

            foreach my $message_key (sort keys %$chunk) {
                my $message = $chunk->{$message_key};

                $message->{'_id'} = $message_key;
                $message->{'_chunk_id'} = $chunk_id;

                push @all_messages, $message;
            }
        }

    } catch {
        warn $_;
    }
}

say STDERR scalar(@all_messages) . " messages to process.";

say STDERR "Writing all messages to STDOUT.";

my $current_player;
foreach my $message (@all_messages) {
    my $type = $message->{'type'};
    my $metadata = "";

    my $new_player = $message->{'who'};
    if($flag_script_mode) {
        if(not defined $current_player or $current_player ne $new_player) {
            say "" if defined $current_player;
            say uc($new_player);
            $message->{'who'} = " ";
        } else {
            $message->{'who'} = " ";
        }
    } else {
        $message->{'who'} = "<" . $message->{'who'} . ">";
    }
    $current_player = $new_player;

    $metadata = " [" . $message->{'_id'} . " #" . 
        $message->{'_chunk_id'} . "]"
        unless $flag_hide_metadata;

    if($type eq 'rollresult' || $type eq 'gmrollresult') {
        my @roll_details;
        my $roll_content = JSON::decode_json($message->{'content'});

        my $result_type;
        given($roll_content->{'resultType'}) {
            when('sum') { $result_type = " + "; }
            default { die "Unknown result type: $_"; }
        };

        foreach my $roll (@{$roll_content->{'rolls'}}) {
            given($roll->{'type'}) {
                when('C') {
                    # Count rolls greater than.
                    push @roll_details, $roll->{'text'};
                }
                when('R') {
                    push @roll_details, sprintf("%dd%d [%s]",
                        $roll->{'dice'},
                        $roll->{'sides'},
                        join(', ', map { $_->{'v'} } @{$roll->{'results'}})
                    );
                }
                when('M') {
                    push @roll_details, $roll->{'expr'};
                }
                default {
                    die "Unknown roll type: '$_': " . Dumper($roll_content);
                }
            }
        }
        
        my $roll_summary = join(" ", @roll_details);
        $roll_summary .= " = ";
        $roll_summary .= $roll_content->{'total'};

        say sprintf("%s%s (rolls %s)",
            $message->{'who'},
            $metadata,
            $roll_summary
        );
    
    } elsif($type eq 'general') {
        say sprintf("%s%s %s",
            $message->{'who'},
            $metadata,
            $message->{'content'}
        );

    } elsif($type eq 'emote') {
        say sprintf("%s%s (%s)",
            $message->{'who'},
            $metadata,
            $message->{'content'}
        )

    } elsif($type eq 'desc') {
        say sprintf("%s%s %s",
            $message->{'who'},
            $metadata,
            $message->{'content'}
        );

    } elsif($type eq 'whisper') {
        say sprintf("%s%s (to %s: %s)",
            $message->{'who'},
            $metadata,
            $message->{'target_name'},
            $message->{'content'}
        );

    } elsif($type eq 'api') {
        # These don't seem to appear? Ignore.

    } else {
        die "Unknown type '$type': " . Dumper($message);
    }
}
