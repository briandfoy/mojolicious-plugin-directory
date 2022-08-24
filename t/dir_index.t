use Mojo::Base qw{ -strict };
use Mojolicious::Lite;

use Mojo::File;

use Test::More;
use Test::Mojo;


my $root = Mojo::File->new(__FILE__)->dirname;
plugin
    'Directory',
    root      => $root->child('dir'),
    dir_index => [qw/index.html index.htm/];

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200);

my $body = $t->tx->res->dom->at('body')->text;
is Mojo::Util::trim($body), 'Hello World';

done_testing();
