use strict;
use Test::More;

my $class = 'Mojolicious::Plugin::Directory' ;
use_ok $class or BAIL_OUT( "$class did not compile: $@" );

done_testing();
