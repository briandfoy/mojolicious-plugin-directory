use Mojo::Base qw{ -strict };
use Mojolicious::Lite;

use Mojo::File;

use Test::More;
use Test::Mojo;

my $dir = Mojo::File->new(__FILE__)->dirname;
plugin 'Directory', root => $dir, auto_index => 0;

my $t = Test::Mojo->new;

$t->get_ok('/')->status_is(404);

done_testing();
