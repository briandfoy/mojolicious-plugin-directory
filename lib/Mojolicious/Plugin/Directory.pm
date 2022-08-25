use v5.20;

package Mojolicious::Plugin::Directory;
use strict;
use warnings;
use experimental qw(signatures);

our $VERSION = '1.001';

use Cwd ();
use Encode ();
use DirHandle;
use Mojo::Base qw{ Mojolicious::Plugin -signatures };
use Mojolicious::Types;
use Mojo::JSON qw(encode_json);

# Stolen from Plack::App::Direcotry
my $default_dir_index_template = <<'PAGE';
<html><head>
  <title>Index of <%= $cur_path %></title>
  <meta http-equiv="content-type" content="text/html; charset=utf-8" />
  <style type='text/css'>
table { width:100%%; }
.name { text-align:left; }
.size, .mtime { text-align:right; }
.type { width:11em; }
.mtime { width:15em; }
  </style>
</head><body>
<h1>Index of <%= $cur_path %></h1>
<hr />
<table>
  <tr>
    <th class='name'>Name</th>
    <th class='size'>Size</th>
    <th class='type'>Type</th>
    <th class='mtime'>Last Modified</th>
  </tr>
  % for my $file (@$files) {
  <tr>
    <td class='name'><a href='<%= $file->{url} %>'><%== $file->{name} %></a></td>
    <td class='size'><%= $file->{size} %></td><td class='type'><%= $file->{type} %></td>
    <td class='mtime'><%= $file->{mtime} %></td>
  </tr>
  % }
</table>
<hr />
</body></html>
PAGE

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Directory - Serve static files from document root with directory index

=head1 SYNOPSIS

  # simple usage
  use Mojolicious::Lite;
  plugin( 'Directory', root => "/path/to/htdocs" )->start;

  # with handler
  use Text::Markdown qw{ markdown };
  use Path::Class;
  use Encode qw{ decode_utf8 };
  plugin('Directory', root => "/path/to/htdocs", handler => sub {
      my ($c, $path) = @_;
      if ( -f $path && $path =~ /\.(md|mkdn)$/ ) {
          my $text = file($path)->slurp;
          my $html = markdown( decode_utf8($text) );
          $c->render( inline => $html );
      }
  })->start;

  or

  > perl -Mojo -E 'a->plugin("Directory", root => "/path/to/htdocs")->start' daemon

=head1 DESCRIPTION

This is a tiny static file server with default directory index files
and auto-creation of directory listings when an index file is not
present.

=head2 register( MOJO_APP, ARGS_HASH_REF )

=over 4

=item * auto_index

(Default: 0) Automatically create a directory listing if there if the
URL path matches a directory and there is no default page present (see
C<dir_index>). This is like Apache's mod_autoindex.

=item * root

(Default: current working dir)

=item * dir_index

(Default: [qw(index.html index.htm)])

This is a different from L<Mojolicious::Plugin::Directory> which had
no default for this.

=item * dir_index_template

(Default: internal templage)

This is a different from L<Mojolicious::Plugin::Directory> which called
this C<dir_page>.

=item * handler

(Default: undef) A code ref to handle a file on your own. Once a file
is located and prepared to be rendered, you can step in and do anything
you like.

  # Mojolicious::Lite
  use Text::Markdown qw{ markdown };
  use Path::Class;
  use Encode qw{ decode_utf8 };
  plugin Directory => {
      handler => sub {
          my ($c, $path) = @_;
          if ($path =~ /\.(md|mkdn)$/) {
              my $text = file($path)->slurp;
              my $html = markdown( decode_utf8($text) );
              $c->render( inline => $html );
          }
      }
  };

=back

=cut

sub register ( $self, $app, $args ) {
	$args->{auto_index}          //= 1;
	$args->{dir_index}           //= [qw(index.html index.htm)];
	$args->{dir_index_template}  //= $default_dir_index_template;
	$args->{root}                //= Cwd::getcwd;

	$args->{root}     = Mojo::File->new($args->{root});

	foreach my $key ( qw(auto_index dir_index dir_index_template handler json root) ) {
		$app->helper( $key => sub { $args->{$key} } );
		}

	my $sub = do {
		if( -f $app->root->to_abs ) {
			@{$app->static->paths} = ();
			$app->static->extra({ $app->root => $app->root->to_abs });
			\&_serve_single_file;
			}
		else {
			@{$app->static->paths} = $app->root->to_abs;
			\&_serve_directory;
			}
		};

	$app->log->debug( "Static paths are <@{$app->static->paths}>" );

    $app->hook( before_dispatch => $sub );

    return $app;
	}

# We don't care what the request path is; we will always serve $c->root
sub _serve_single_file ( $c ) {
	_render_file( $c, $c->root, $c->handler )
	}

sub _serve_directory ( $c ) {
	# can't just remove trailing slash because that screws around with
	# redirects in some way I don't understand.
	my $path = $c->root->child( Mojo::Util::url_unescape( $c->req->url->path ) )->to_rel;

	if ( -f $path ) {
		_render_file( $c, $path, $c->handler );
		}
	elsif ( -d $path ) {
		if( $c->dir_index && ( my $index_path = _locate_index( $c->dir_index, $path ) ) ) {
			return _render_file( $c, $index_path, $c->handler );
			}

		if( $c->req->url->path ne '/' && ! $c->req->url->path->trailing_slash ) {
			$c->redirect_to($c->req->url->path->trailing_slash(1));
			return;
			}

		if( $c->auto_index ) {
			_render_indexes( $c, $path, $c->json );
			}
		else {
			$c->reply->not_found;
			}
		}
	}

sub _locate_index ( $index, $dir = Cwd::getcwd ) {
    return unless $index;
    my $root  = Mojo::File->new( $dir );
    $index = ( ref $index eq 'ARRAY' ) ? $index : [$index];
    for (@$index) {
        my $path = $root->child($_);
        return $_ if -e $path;
    }
}

sub _render_file ( $c, $path, $handler ) {
    $handler->( $c, $path ) if ref $handler eq 'CODE';
    return if $c->tx->res->code;
    $c->stash( path => $path );
    $c->reply->static($path);
}

sub _render_indexes ( $c, $dir, $json ) {
    my @files =
        ( $c->req->url->path eq '/' )
        ? ()
        : ( { url => '../', name => 'Parent Directory', size => '', type => '', mtime => '' } );
    my $children = _list_files($dir);

    my $cur_path = Encode::decode_utf8( Mojo::Util::url_unescape( $c->req->url->path ) );
    for my $basename ( sort { $a cmp $b } @$children ) {
    	state $types = Mojolicious::Types->new;

        my $file = "$dir/$basename";
        my $url  = Mojo::Path->new($cur_path)->trailing_slash(0);
        push @{ $url->parts }, $basename;

        my $is_dir = -d $file;
        my @stat   = stat _;
        if ($is_dir) {
            $basename .= '/';
            $url->trailing_slash(1);
        }

        my $mime_type =
            $is_dir
            ? 'directory'
            : ( $types->type( _get_ext($file) || 'txt' ) || 'text/plain' );
        my $mtime = Mojo::Date->new( $stat[9] )->to_string();

        push @files, {
            url   => $url,
            name  => $basename,
            size  => $stat[7] || 0,
            type  => $mime_type,
            mtime => $mtime,
        };
    }

    my $any = { inline => $c->dir_index_template, files => \@files, cur_path => $cur_path };
    if ($json) {
        $c->respond_to(
            json => { json => encode_json(\@files) },
            any  => $any,
        );
    }
    else {
        $c->render( %$any );
    }
}

sub _get_ext ( $file ) {
    $file =~ /\.([0-9a-zA-Z]+)$/ || return;
    return lc $1;
}

sub _list_files ( $dir ) {
    return [] unless $dir;
    my $dh = DirHandle->new($dir);
    my @children;
    while ( defined( my $ent = $dh->read ) ) {
        next if $ent eq '.' or $ent eq '..';
        push @children, Encode::decode_utf8($ent);
    }
    return [ @children ];
}

1;

=head1 AUTHOR

Original author of L<Mojolicious::Plugin::Directory>: hayajo E<lt>hayajo@cpan.orgE<gt>

This version is heavily adapted by brian d foy, E<lt>bdfoy@cpan.orgE<gt>

=head1 CONTRIBUTORS

Many thanks to the contributors for their work.

=over 4

=item * hayajo E<lt>hayajo@cpan.orgE<gt>

=item * ChinaXing

=back

=head1 SEE ALSO

L<Plack::App::Directory>, L<Mojolicious::Plugin::Directory>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
