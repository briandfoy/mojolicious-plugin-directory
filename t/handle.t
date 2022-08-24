use Mojo::Base qw{ -strict };
use Mojolicious::Lite;

use Encode;
use Mojo::File;

use Test::More;
use Test::Mojo;


my $root = Mojo::File->new(__FILE__)->dirname;
plugin 'Directory', root => $root, handler => sub {
    my ($c, $path) = @_;
    $c->render( data => $path, format => 'txt' ) if (-f $path);
};


my $t = Test::Mojo->new();
$t->get_ok('/')->status_is(200);

my $location_is = sub {
  my ($t, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  return $t->success(like($t->tx->res->headers->location, $regex));
};

subtest 'entries' => sub {
    my $dh = DirHandle->new($root);
    while ( defined( my $ent = $dh->read ) ) {
        next if $ent eq '.' or $ent eq '..';
        $ent = Encode::decode_utf8($ent);
        my $path = $root->child($ent);
        if (-f $path) {
            $t->get_ok("/$ent")->status_is(200)->content_is( Encode::encode_utf8($path) );
        }
        elsif (-d $path) {
            $t->get_ok("/$ent")->status_is(302)->$location_is(qr|/$ent/$|);
            $t->get_ok("/$ent/")->status_is(200)->content_like( qr/Parent Directory/ );
        }
        else { ok 0 }
    }
};

done_testing();
