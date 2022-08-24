use Mojo::Base qw{ -strict };
use Mojolicious::Lite;

use Mojo::File;

use Test::More;
use Test::Mojo;

my $root = Mojo::File->new(__FILE__)->dirname;

plugin 'Directory', root => $root, dir_index => [], dir_page => <<'EOF';
entries: <%= scalar @$files %>
EOF

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200);

use File::Basename;
subtest 'entries' => sub {
    my $dh = DirHandle->new($root);
    my $entries;
    while ( defined( my $ent = $dh->read ) ) {
        next if -d $ent or $ent eq '.' or $ent eq '..';
        $entries++;
    }
    $t->get_ok('/')->status_is(200)->content_like( qr<Index of /> );
};

done_testing();
