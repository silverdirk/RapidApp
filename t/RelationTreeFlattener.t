#! /usr/bin/perl

package FakeSource;

our %sources= (
	Object   => bless({ columns => [qw[ id owner_id creator_id is_deleted ]], rels => { user => 'User', contact => 'Contact', owner => 'User', creator => 'User' } }),
	User     => bless({ columns => [qw[ object_id username password ]], rels => {} }),
	Contact  => bless({ columns => [qw[ object_id first last timezone_id ]], rels => { timezone => 'Timezone' } }),
	Timezone => bless({ columns => [qw[ id name abbrev ofs ]], rels => {} }),
);

sub columns {
	@{ $_[0]->{columns} }
}
sub has_relationship {
	$_[0]->{rels}->{$_[1]}
}
sub related_source {
	my $srcN= $_[0]->{rels}->{$_[1]};
	$sources{$srcN};
}

package FakeSchema;
sub source {
	$FakeSource::sources{$_[1]} or die "No such source: $_[1]";
}

package main;
use strict;
use Test::More;
use Try::Tiny;

use_ok('RapidApp::DBIC::RelationTreeSpec');
use_ok('RapidApp::DBIC::RelationTreeFlattener');

my $db= 'FakeSchema';

my $spec= RapidApp::DBIC::RelationTreeSpec->new(
	source => $db->source('Object'),
	colSpec => [qw( user.* contact.* creator_id owner_id is_deleted contact.timezone.ofs )]
);

my $flattener= RapidApp::DBIC::RelationTreeFlattener->new(spec => $spec, ignoreUnexpected => 0);

my $treed= {
	creator_id => 5,
	owner_id => 7,
	is_deleted => 0,
	user => { username => 'foo', password => 'yes' },
	contact => {
		first => 'John',
		last => 'Doe',
		timezone => { ofs => -500 }
	},
};
my $flattened= {
	creator_id => 5,
	owner_id => 7,
	is_deleted => 0,
	user_username => 'foo',
	user_password => 'yes',
	contact_first => 'John',
	contact_last => 'Doe',
	contact_timezone_ofs => -500,
};
  
is_deeply( $flattener->flatten($treed), $flattened, 'flatten a tree' );
is_deeply( $flattener->restore($flattened), $treed, 'restore a tree' );

done_testing;
