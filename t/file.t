use Mojo::Base qw{ -strict };
use Mojolicious::Lite;

use Mojo::File;

use Test::More;
use Test::Mojo;

my $root = Mojo::File->new(__FILE__)->dirname;
plugin 'Directory', root => $root->child( 'dummy.txt' );

my $t = Test::Mojo->new();

my $pattern = qr/^DUMMY\R*\z/;
$t->get_ok('/')->status_is(200)->content_like($pattern);
$t->get_ok('/foo/bar/buz')->status_is(200)->content_like($pattern);

done_testing();
