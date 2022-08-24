use Mojo::Base qw{ -strict };
use Mojolicious::Lite;

use Encode ();
use Mojo::File;

use Test::More;
use Test::Mojo;

use version;

my $dir = Mojo::File->new(__FILE__)->dirname;
plugin 'Directory', root => $dir, json => 1;

my $t = Test::Mojo->new;

subtest 'entries' => sub {
    $t->get_ok('/')->status_is(200);

    my $dh = DirHandle->new($dir);
    while ( defined( my $ent = $dh->read ) ) {
        next if $ent eq '.' or $ent eq '..';
        $ent = Encode::decode_utf8($ent);
        $t->content_like(qr/$ent/);
    }
};

subtest 'json' => sub {
    my $res = $t->get_ok('/?_format=json')->status_is(200);
    if ( version->parse($Mojolicious::VERSION)->numify >= version->parse('6.09')->numify ) {
        $res->content_type_is('application/json;charset=UTF-8');
    } else {
        $res->content_type_is('application/json');
    }
};

done_testing();
