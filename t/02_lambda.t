#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use FindBin qw/$RealBin/;

use lib "$RealBin/../lib";
use File::Basename qw/dirname basename/;
use File::Temp qw/tempdir/;
use File::Copy qw/cp/;
use Digest::MD5 qw/md5_hex/;

use Test::More tests => 7;

use_ok 'Mashtree';
use Mashtree qw/treeDist mashDist raw_mash_distance mashHashes/;

$ENV{PATH}="./bin:$ENV{PATH}";

my $tempdir = tempdir(basename($0).".XXXXXX", TMP=>1, CLEANUP=>1);

subtest 'space in filename' => sub {
  my $wd = "$tempdir/spaces";
  mkdir $wd;
  my @target;
  for my $filename(glob("$RealBin/lambda/*.fastq.gz")){
    my $target = "$wd/".basename($filename);
    $target =~ s/sample(\d)/sample $1/; # add in a space for funsies
    cp($filename, $target) or die "ERROR: could not copy $filename to $target: $!";

    push(@target, $target);
  }

  # e.g., '02_lambda.tmp.tiF_bn/spaces/sample 1.fastq.gz' '02_lambda.tmp.tiF_bn/spaces/sample 2.fastq.gz' '02_lambda.tmp.tiF_bn/spaces/sample 3.fastq.gz' '02_lambda.tmp.tiF_bn/spaces/sample 4.fastq.gz'
  my $targets = "'" . join("' '", @target) . "'";
  my $cmd = "mashtree --outmatrix lambdadist.tsv --genomesize 40000 --numcpus 1 $targets 2>$0.log";
  note $cmd;
  system($cmd);
  my $exit_code = $? >> 8;
  if($exit_code){
    note `cat $0.log`;
  }
  is($exit_code, 0, "Ran mashtree with exit code $exit_code");
};

my $correctMashtree="(sample3:0.00195,sample4:0.00205,(sample1:0.00205,sample2:0.00205):0.00010);";
$correctMashtree=~s/(\d+\.)(\d+)/$1 . substr($2,0,4)/ge; # global and expression

# Test to see if the correct tree is made
END{unlink "lambdadist.tsv"; unlink "$0.log";}
my $mashtree=`mashtree --outmatrix lambdadist.tsv --genomesize 40000 --save-sketches $RealBin/lambda/sketches --numcpus 1 $RealBin/lambda/*.fastq.gz 2>$0.log`;
if($?){
  BAIL_OUT("ERROR running mashtree: $!\n ".`cat $0.log`);
}
chomp($mashtree);
$mashtree=~s/(\d+\.)(\d+)/$1 . substr($2,0,4)/ge; # global and expression
my $dist=treeDist($mashtree,$correctMashtree);
is $dist , 0, "Lambda test set tree, distance should be zero between trees";
if($dist!=0){
  note "Correct tree: $correctMashtree";
  note "This tree:    $mashtree";
  BAIL_OUT("Incorrect tree found. Will not continue.");
}

# Test for the correct distance matrix
my %matrix=(
          'sample4' => {
                         'sample4' => 0,
                         'sample2' => '0.00417555',
                         'sample1' => '0.0042153'
                       },
          'sample2' => {
                         'sample2' => 0,
                         'sample1' => '0.00414809'
                       },
          'sample3' => {
                         'sample4' => '0.00402957',
                         'sample2' => '0.00405078',
                         'sample3' => 0,
                         'sample1' => '0.0041298'
                       },
          'sample1' => {
                         'sample1' => 0
                       }
        );
# mirror the matrix
while(my($ref,$queryHash)=each(%matrix)){
  while(my($query,$dist)=each(%$queryHash)){
    $matrix{$query}{$ref}=$dist;
  }
}

subtest "Test matrix" => sub {
  plan tests => 16;
  open(MATRIX, "lambdadist.tsv") or die "ERROR: could not read lambdadist.tsv: $!";
  my $header=<MATRIX>;
  chomp($header);
  my (undef,@header)=split(/\t/,$header);
  while(my $distances=<MATRIX>){
    chomp($distances);
    my($label,@dist)=split /\t/,$distances;
    for(my $i=0;$i<@header;$i++){
      is $dist[$i], $matrix{$label}{$header[$i]}, "Distance between $label and $header[$i]"
        or note "Should have been $dist[$i]";
    }
  }
  close MATRIX;
};

# Did we get exactly the right sketches?
my %sketches = (
  "$RealBin/lambda/sketches/sample1.fastq.gz.msh" => "3b11eed05ee26156758e3df04816e742",
  "$RealBin/lambda/sketches/sample2.fastq.gz.msh" => "3b11eed05ee26156758e3df04816e742",
  "$RealBin/lambda/sketches/sample3.fastq.gz.msh" => "3b11eed05ee26156758e3df04816e742",
  "$RealBin/lambda/sketches/sample4.fastq.gz.msh" => "3b11eed05ee26156758e3df04816e742",
);
subtest "Saving sketches" => sub {
  plan tests => 4;
  for my $file(sort keys(%sketches)){
    my $md5sum = $sketches{$file};
    open(my $fh, "mash info $file | ") or die "ERROR running mash info on $file: $!";
    my @content = grep {!/sample/} <$fh>;
    close $fh;
    my $content = join("", @content);
    pass("TODO: check md5sum, host computer agnostic"); next;
    is(md5_hex($content), $md5sum, "MD5 of ".basename($file))
      or note "Should have been $sketches{$file}. Check on file size and/or `mash info` to follow up.";
  }
};

# test Mash module functions
# # 8460/10000
my ($hashes1, $k1, $length1) = mashHashes("$RealBin/lambda/sketches/sample1.fastq.gz.msh");
my ($hashes2, $k2, $length2) = mashHashes("$RealBin/lambda/sketches/sample2.fastq.gz.msh");
my ($common, $total) = raw_mash_distance($hashes1, $hashes2);
is($common/$total, 8460/10000, "Raw mash distance")
  or note "Got: $common / $total but it should be 8460/10000";

my $mashDist = mashDist("$RealBin/lambda/sketches/sample1.fastq.gz.msh","$RealBin/lambda/sketches/sample2.fastq.gz.msh");
is(sprintf("%0.8f",$mashDist), 0.00414809, "Mash distance function");

