use Mojo::Base qw{ -strict };
use Mojolicious::Lite;

use Test::More;
use Test::Mojo;

plugin 'Directory';

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200);

subtest 'entries' => sub {
    my $dh = DirHandle->new('.');
    while ( defined( my $ent = $dh->read ) ) {
        next if $ent eq '.' or $ent eq '..';
        $t->content_like(qr/$ent/);
    }
};

done_testing();
