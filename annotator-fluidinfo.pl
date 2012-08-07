#! /usr/bin/perl

# Fluidinfo backend store for Annotator

use Mojo::Base 'Mojolicious';
use Net::Fluidinfo;
use POSIX qw(strftime);

use strict;

my %annotations;
my $lastid = 1;

($ENV{FLUIDINFO_USERNAME} && $ENV{FLUIDINFO_PASSWORD})
	or die "$0: Need to set FLUIDINFO_USERNAME and FLUIDINFO_PASSWORD\n";
my $fin = Net::Fluidinfo->new;

my $nspath = "$ENV{FLUIDINFO_USERNAME}/annotator";
my $ns = $fin->get_namespace($nspath);

my @taglist = qw(annotator_schema version created updated text quote related-url
				 ranges/start ranges/end ranges/startOffset ranges/endOffset
				 user consumer tags);
# Set up tags
if (!$ns) {
	$ns = Net::Fluidinfo::Namespace->new(fin => $fin, path => $nspath);
	$ns->create;
	foreach my $tagname (@taglist) {
		my $tag = Net::Fluidinfo::Tag->new(fin => $fin,
										   indexed => 1,
										   path => "$nspath/$tagname");
		$tag->create;
	}
}

my $app = Mojolicious->new;
my $r = $app->routes;

sub object_to_hash
{
	my $obj = shift;
	my %hash;

	foreach my $tagpath (@{$obj->tag_paths}) {
		(my $tagname = $tagpath) =~ s#^$nspath/## or next;
		my ($n1, $n2) = split m#/#, $tagname;
		my $value = $obj->value($tagpath) or next;
		if ($n2) { $hash{$n1}{$n2} = $value }
		else { $hash{$tagname} = $value }
	}
	$hash{id} = $obj->id;
	if (exists $hash{'related-url'}) {
		$hash{'uri'} = $hash{'related-url'};
		delete $hash{'related-url'};
	}

	## For the time being, annotations are limited to one range
	$hash{ranges} = [ $hash{ranges} ] if $hash{ranges};

	return \%hash;
}

sub hash_to_object
{
	my ($hash, $obj) = @_;

	if (exists $hash->{uri}) {
		$hash->{'related-url'} = $hash->{uri};
		delete $hash->{uri};
	}

	## For the time being, limit an annotation to one range
	$hash->{ranges} = $hash->{ranges}[0] if $hash->{ranges};

	if (!$obj) {
		$obj = Net::Fluidinfo::Object->new(fin => $fin);
		$obj->create;
	}
	foreach my $tagname (@taglist) {
		my ($n1, $n2) = split m#/#, $tagname;
		my $value = ($n2 && exists $hash->{$n1}) 
					? $hash->{$n1}{$n2} : $hash->{$tagname};
		$obj->tag("$nspath/$tagname", string => $value) if $value;
	}

	$obj;
}

# Endpoints

$r->get('/' => sub {
	$_[0]->render_json({ name => 'Fluidinfo Store for Annotator',
						 version => '1.0' });
});

$r->get('/annotations' => sub {
	my $c = shift;
	my @annotations;
	foreach my $id ($fin->search("has $nspath/text")) {
		my $ann = object_to_hash($fin->get_object_by_id($id));
		push @annotations, $ann;
	}
	$c->render_json(\@annotations);
});
$r->get('/annotations/:id' => sub {
	my $c = shift;
	my $obj = $fin->get_object_by_id($c->stash('id'));
	if ($obj) {
		my $ann = object_to_hash($obj);
		$c->render_json($ann);
	}
	else { $c->render_not_found }
});
$r->post('/annotations' => sub {
	my $c = shift;
	my $ann = $c->req->json;
	$ann->{created} = $ann->{updated} = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime);
	my $obj = hash_to_object($ann);
	$ann->{id} = $obj->id;
	$c->render_json($ann);
});
$r->put('/annotations/:id' => sub {
	my $c = shift;
	my $obj = $fin->get_object_by_id($c->stash('id'))
		or $c->render_not_found, return;
	my $mods = $c->req->json;
	$mods->{updated} = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime);
	hash_to_object($mods, $obj);
	$c->render_json(object_to_hash($obj));
});
$r->delete('/annotations/:id' => sub {
	my $c = shift;	
	my $obj = $fin->get_object_by_id($c->stash('id'));
	if (!$obj || !$obj->value("$nspath/text")) {
		$c->render_not_found;
		return;
	}
	foreach my $tagpath (@{$obj->tag_paths}) { $obj->untag($tagpath) }
	$c->render_data('', status => 204);
});
$r->options('/annotation*' => sub { 
	my $c = shift;
	$c->res->headers->header(Allow => 
							 ('POST', 'HEAD', 'OPTIONS', 'GET'));
	$c->res->headers->header('Access-Control-Allow-Methods' => 
							 ('GET, POST, PUT, DELETE, OPTIONS'));
	$c->res->headers->header('Access-Control-Allow-Headers' => 
							 ('Content-Length, Content-Type, X-Annotator-Auth-Token, X-Requested-With'));
	$c->res->headers->header('Access-Control-Max-Age' => 86400);
	$c->render_data('');
});

$r->get('/search' => sub {
	my $c = shift;
	my $total = 0; my @matches;
	my ($attr, $val) = %{ $c->req->params->to_hash };
	$attr = 'related-url' if $attr eq 'uri';
	foreach my $id ($fin->search(qq($nspath/$attr matches "$val"))) {
		push @matches, object_to_hash($fin->get_object_by_id($id));
	}
	$total = @matches;
	$c->render_json({ total => $total, rows => [ @matches ] });
});

$app->hook(after_dispatch => sub {
	my $c = shift;
	$c->res->headers->header('Access-Control-Allow-Origin' =>
								$c->req->headers->header('Origin') || '*');
	$c->res->headers->header('Access-Control-Expose-Headers' => 'Content-Length, Content-Type, Location');
});

$app->start(@ARGV || 'daemon');
