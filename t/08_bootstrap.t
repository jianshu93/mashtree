#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use FindBin qw/$RealBin/;
use lib "$RealBin/../lib";
use File::Basename qw/dirname/;
use File::Path qw/rmtree/;
use Bio::TreeIO;
use IO::String;
use Scalar::Util qw/looks_like_number/;

use Test::More tests => 3;

use_ok 'Mashtree';
use Mashtree;
use Mashtree::Db;

$ENV{PATH}="$RealBin/../bin:$ENV{PATH}";

my $correctMashtree="((sample2:0.0020443525,sample1:0.0021037373)66:0.0000540274,sample3:0.0019622177,sample4:0.0020673526)83;";
$correctMashtree=~s/(\d+\.)(\d+)/$1 . substr($2,0,4)/ge; # global and expression

# Cleanup
END{
  rmtree("$RealBin/lambda/bootstrap.tmp");
  unlink("$RealBin/lambda/bootstrap.log");
}

subtest "run mashtree" => sub{
  # Test to see if the correct tree is made
  my $mashtree=`mashtree_bootstrap.pl --tempdir $RealBin/lambda/bootstrap.tmp --reps 10 --numcpus 2 $RealBin/lambda/*.fastq.gz 2>$RealBin/lambda/bootstrap.log`;
  if($?){
    my $log = `cat $RealBin/lambda/bootstrap.log`;
    diag $log;
    BAIL_OUT("mashtree_bootstrap.pl exited with an error code $?");
  }
  my $passed = ok(defined($mashtree),"Mashtree_bootstrap.pl ran and produced a string");
  $mashtree=~s/(\d+\.)(\d+)/$1 . substr($2,0,4)/ge; # global and expression

  my $fh = IO::String->new($mashtree);
  my $tree = Bio::TreeIO->new(-fh=>$fh, -format=>"newick")->next_tree;
  $passed = is(ref($tree),"Bio::Tree::Tree","Produced a BioPerl tree object");
  if(!$passed){
    diag "Tree string produced was $mashtree";
    BAIL_OUT("Tree object was not produced out of the tree string");
  }

  subtest "Parts of the tree file intact" => sub{
    plan tests => 3;
    my @nodes = $tree->get_nodes;
    my @expectedBootstrap = (100, 11);
    my $nodeCounter=0;
    for my $node(grep {!$_->is_Leaf} @nodes){
      ok(looks_like_number($node->id), "Bootstrap is a number: ".$node->id);
      note("Usually this bootstrap is around $expectedBootstrap[$nodeCounter], give or take 5%");
      $nodeCounter++;
    }

    my $correctNodeString = "sample1 sample2 sample3 sample4";
    my $nodeString = join(" ", sort map{$_->id} grep { $_->is_Leaf} @nodes);
    is $correctNodeString, $nodeString, "Taxon names in the tree: $nodeString";
  };

};

# Address the bug fix https://github.com/lskatz/mashtree/issues/51#issuecomment-604495598
subtest "file-of-filenames" => sub{
  plan tests=>2;

  # Make the file of filenames
  my $fofn = "$RealBin/lambda/lambda.fofn";
  my @file = glob("$RealBin/lambda/*.fastq.gz");
  open(my $fh, ">", $fofn) or die "ERROR: could not write to $fofn: $!";
  for my $f(@file){
    print $fh "$f\n";
  }
  close $fh;

  my $mashtreeFofn = `mashtree_bootstrap.pl --tempdir $RealBin/lambda/bootstrap.tmp --reps 100 --numcpus 2 --file-of-files $fofn 2>$RealBin/lambda/bootstrap.log`;
  note "mashtree text is: $mashtreeFofn";
  
  my $treeFh = IO::String->new($mashtreeFofn);
  my $tree = Bio::TreeIO->new(-fh=>$treeFh, -format=>"newick")->next_tree;
  my $passed = is(ref($tree),"Bio::Tree::Tree","Produced a BioPerl tree object");
  if(!$passed){
    diag "Tree string produced was $tree";
    BAIL_OUT("Tree object was not produced out of the tree string");
  }

  my @leaf = sort map{$_->id} grep{$_->is_Leaf} $tree->get_nodes;
  is(scalar(@leaf), 4, "correct number of nodes");
  note "@leaf";
};

