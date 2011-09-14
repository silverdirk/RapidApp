package RapidApp::AppGrid2;


use strict;
use Moose;

extends 'RapidApp::AppCmp';

use RapidApp::Include qw(sugar perlutil);

#use RapidApp::DataStore2;

with 'RapidApp::Role::DataStore2';

use Try::Tiny;

use RapidApp::Column;

has 'record_pk'			=> ( is => 'ro', default => 'id' );
has 'DataStore_class'	=> ( is => 'ro', default => 'RapidApp::DataStore2', isa => 'ClassName' );


has 'title' => ( is => 'ro', default => undef );
has 'title_icon_href' => ( is => 'ro', default => undef );

has 'open_record_class' => ( is => 'ro', default => undef, isa => 'Maybe[ClassName|HashRef]' );
has 'add_record_class' => ( is => 'ro', default => undef, isa => 'Maybe[ClassName|HashRef]' );


# autoLoad needs to be false for the paging toolbar to not load the whole
# data set
has 'store_autoLoad' => ( is => 'ro', default => sub {\0} );

has 'add_loadContentCnf' => ( is => 'ro', default => sub {
	{
		title		=> 'Add',
		iconCls	=> 'icon-add'
	}
});

has 'add_button_cnf' => ( is => 'ro', default => sub {
	{
		text		=> 'Add',
		iconCls	=> 'icon-add'
	}
});

# Either based on open_record_class, or can be set manually in the constructor:
has 'open_record_url' => ( is => 'ro', isa => 'Maybe[Str]', lazy => 1, default => sub {
  my $self = shift;
  return $self->Module('item',1)->base_url if ($self->open_record_class);
  return undef;
});


# get_record_loadContentCnf is used on a per-row basis to set the 
# options used to load the row in a tab when double-clicked
# This should be overridden in the subclass:
sub get_record_loadContentCnf {
	my ($self, $record) = @_;
	
	return {
		title	=> $self->record_pk . ': ' . $record->{$self->record_pk}
	};
}

has 'init_pagesize' => ( is => 'ro', isa => 'Int', default => 25 );
has '+max_pagesize' => ( default => 500 );

sub BUILD {
	my $self = shift;
	
	$self->apply_config(
		xtype						=> 'appgrid2',
		pageSize					=> $self->init_pagesize,
		maxPageSize				=> $self->max_pagesize,
		stripeRows				=> \1,
		columnLines				=> \1,
		use_multifilters		=> \1,
		gridsearch				=> \1,
		gridsearch_remote		=> \1,
		column_allow_save_properties => [ 'width','hidden' ]
	);
	
	# The record_pk is forced to be added/included as a column:
	if (defined $self->record_pk) {
		$self->apply_columns( $self->record_pk => {} );
		push @{ $self->include_columns }, $self->record_pk if (scalar @{ $self->include_columns } > 0);
		#$self->meta->find_attribute_by_name('include_columns_hash')->clear_value($self);
		%{ $self->include_columns_hash } = ();
	}
	
	if (defined $self->open_record_class) {
		$self->apply_init_modules( item => $self->open_record_class );
		
		# reach into the new sub-module and add a write listener to its store to
		# make it call our store.load() whenever it changes:
		$self->Module('item',1)->DataStore->add_listener( write => $self->DataStore->store_load_fn ) if (
			$self->Module('item',1)->does('RapidApp::Role::DataStore2')
		);
	}
	
	if (defined $self->add_record_class) {
		$self->apply_init_modules( add => $self->add_record_class );
		
		# reach into the new sub-module and add a write listener to its store to
		# make it call our store.load() whenever it changes:
		$self->Module('add',1)->DataStore->add_listener( write => $self->DataStore->store_load_fn ) if (
			$self->Module('add',1)->does('RapidApp::Role::DataStore2')
		);
	}
	
	
	
	if (defined $self->open_record_url or defined $self->add_record_class) {
		$self->add_listener(	beforerender => RapidApp::JSONFunc->new( raw => 1, func => 
			'Ext.ux.RapidApp.AppTab.cnt_init_loadTarget' 
		));
	}
	
	if (defined $self->open_record_url) {
    $self->add_listener( rowdblclick => RapidApp::JSONFunc->new( raw => 1, func => 
			'Ext.ux.RapidApp.AppTab.gridrow_nav' 
		));
  }
	
	
	
	
	
	$self->apply_actions( save_search => 'save_search' ) if ( $self->can('save_search') );
	$self->apply_actions( delete_search => 'delete_search' ) if ( $self->can('delete_search') );
	
	$self->DataStore->add_read_raw_mungers(RapidApp::Handler->new( scope => $self, method => 'add_loadContentCnf_read_munger' ));
	
	$self->add_ONREQUEST_calls('init_onrequest');
	$self->add_ONREQUEST_calls_late('init_delete_enable');
}

sub init_onrequest {
	my $self = shift;
		
	#$self->apply_config(store => $self->JsonStore);
	$self->apply_config(tbar => $self->tbar_items) if (defined $self->tbar_items);
}



sub init_delete_enable {
	my $self = shift;
	if($self->can('action_delete_records') and $self->has_flag('can_delete')) {
	#if($self->can('action_delete_records')) {
		my $act_name = 'delete_rows';
		$self->apply_actions( $act_name => 'action_delete_records' );
		$self->apply_extconfig( delete_url => $self->suburl($act_name) );
	}
}




sub add_loadContentCnf_read_munger {
	my $self = shift;
	my $result = shift;
	
	# Add a 'loadContentCnf' field to store if open_record_class is defined.
	# This data is used when a row is double clicked on to open the open_record_class
	# module in the loadContent handler (JS side object). This is currently AppTab
	# but could be other JS classes that support the same API
	if (defined $self->open_record_url) {
		foreach my $record (@{$result->{rows}}) {
			my $loadCfg = {};
			# support merging from existing loadContentCnf already contained in the record data:
			$loadCfg = $self->json->decode($record->{loadContentCnf}) if (defined $record->{loadContentCnf});
			
			%{ $loadCfg } = (
				%{ $self->get_record_loadContentCnf($record) },
				%{ $loadCfg }
			);
			
			unless (defined $loadCfg->{autoLoad}) {
				$loadCfg->{autoLoad} = {};
				$loadCfg->{autoLoad}->{url} = $loadCfg->{url} if ($loadCfg->{url});
			}
			
			$loadCfg->{autoLoad}->{url} = $self->open_record_url unless (defined $loadCfg->{autoLoad}->{url});
			
			$record->{loadContentCnf} = $self->json->encode($loadCfg);
		}
	}
}



=pod
around 'store_read_raw' => sub {
	my $orig = shift;
	my $self = shift;
	
	my $result = $self->$orig(@_);
	
	# Add a 'loadContentCnf' field to store if open_record_class is defined.
	# This data is used when a row is double clicked on to open the open_record_class
	# module in the loadContent handler (JS side object). This is currently AppTab
	# but could be other JS classes that support the same API
	if (defined $self->open_record_class) {
		foreach my $record (@{$result->{rows}}) {
			my $loadCfg = {};
			# support merging from existing loadContentCnf already contained in the record data:
			$loadCfg = $self->json->decode($record->{loadContentCnf}) if (defined $record->{loadContentCnf});
			
			%{ $loadCfg } = (
				%{ $self->get_record_loadContentCnf($record) },
				%{ $loadCfg }
			);
			
			$loadCfg->{autoLoad} = {} unless (defined $loadCfg->{autoLoad});
			$loadCfg->{autoLoad}->{url} = $self->Module('item')->base_url unless (defined $loadCfg->{autoLoad}->{url});
			
			
			$record->{loadContentCnf} = $self->json->encode($loadCfg);
		}
	}

	return $result;
};
=cut


sub options_menu_items {
	my $self = shift;
	return undef;
}


sub options_menu {
	my $self = shift;
	
	my $items = $self->options_menu_items or return undef;
	return undef unless (ref($items) eq 'ARRAY') && scalar(@$items);
	
	return {
		xtype		=> 'button',
		text		=> 'Options',
		iconCls	=> 'icon-gears',
		menu => {
			items	=> $items
		}
	};
}



sub tbar_items {
	my $self = shift;
	
	my $arrayref = [];
	
	push @{$arrayref}, '<img src="' . $self->title_icon_href . '" />' 		if (defined $self->title_icon_href);
	push @{$arrayref}, '<b>' . $self->title . '</b>'								if (defined $self->title);

	my $menu = $self->options_menu;
	push @{$arrayref}, ' ', '-',$menu if (defined $menu); 
	
	push @{$arrayref}, '->';
	
	push @{$arrayref}, $self->add_button if (
		defined $self->add_record_class and
		$self->show_add_button
	);

	return (scalar @{$arrayref} > 1) ? $arrayref : undef;
}
sub show_add_button { 1 }

sub add_button {
	my $self = shift;
	
	my $loadCfg = {
		url => $self->suburl('add'),
		%{ $self->add_loadContentCnf }
	};
	
	my $handler = RapidApp::JSONFunc->new( raw => 1, func =>
		'function(btn) { btn.ownerCt.ownerCt.loadTargetObj.loadContent(' . $self->json->encode($loadCfg) . '); }'
	);
	
	return RapidApp::JSONFunc->new( func => 'new Ext.Button', parm => {
		handler => $handler,
		%{ $self->add_button_cnf }
	});
}




sub set_all_columns_hidden {
	my $self = shift;
	return $self->apply_to_all_columns(
		hidden => \1
	);
}


sub set_columns_visible {
	my $self = shift;
	my @cols = (ref($_[0]) eq 'ARRAY') ? @{ $_[0] } : @_; # <-- arg as array or arrayref
	return $self->apply_columns_list(\@cols,{
		hidden => \0
	});
}


sub web1_render_extcfg {
	my ($self, $renderCxt, $extCfg)= @_;
	
	# simulate a get request to the grid's store
	my $storeFetchParams= $extCfg->{store}{parm}{baseParams};
	my $origParams= $self->c->req->params;
	my $data;
	try {
		$self->c->req->params($storeFetchParams);
		$data= $self->Module('store')->read();
		$self->c->req->params($origParams);
	}
	catch {
		$self->c->req->params($origParams);
		die $_;
	};
	
	my $cols= $extCfg->{columns};
	defined $cols && ref $cols eq 'ARRAY'
		or $cols= [];
	
	# filter hidden columns
	$cols= [ grep { !$_->{hidden} || (ref $_->{hidden} && !${$_->{hidden}}) } @$cols ];
	
	# now render it using the xtype_panel code
	$renderCxt->renderer->render_xtype_panel($renderCxt, {
		%$extCfg,
		bbar => undef, # skip bottom bar, since web 1.0 doesn't need the buttons
		bodyContent => sub { $self->web1_render_table($renderCxt, $extCfg, $cols, $data->{rows}) },
	});
}

sub web1_render_table {
	my ($self, $renderCxt, $extCfg, $cols, $rows)= @_;
	$renderCxt->incCSS('/static/rapidapp/css/web1_ExtJSGrid.css');
	
	# write table
	$renderCxt->write("<div class='x-grid3'><div class='x-grid3-viewport'><table style='width:100%'>\n");
	
	# write header cells
	$renderCxt->write('<tr class="x-grid3-hd-row x-grid3-header">');
	$renderCxt->write(join('', map { '<th class="x-grid3-hd x-grid3-cell" width="'.$_->{width}.'"><div class="x-grid3-hd-inner">'.$_->{header}.'</div></th>' } @$cols ));
	$renderCxt->write("</tr>\n");
	
	# write data cells
	if (scalar(@$rows)) {
		for my $row (@$rows) { $self->web1_render_table_row($renderCxt, $extCfg, $cols, $row); }
	}
	else {
		my $span= scalar(@$cols) > 1? ' colspan="'.scalar(@$cols).'"' : '';
		my $emptyText= defined $extCfg->{viewConfig} && $extCfg->{viewConfig}{emptyText};
		$renderCxt->write("<tr><td class='x-grid-empty'$span>".$emptyText."</td></tr>");
	}
	
	$renderCxt->write("</table></div></div>\n");
}

sub web1_render_table_row {
	my ($self, $renderCxt, $extCfg, $cols, $row)= @_;
	$renderCxt->write('<tr>'.join('', map { '<td class="x-grid3-col x-grid3-cell">'.$row->{$_->{dataIndex}}.'</td>' } @$cols )."</tr>\n");
}

#### --------------------- ####


no Moose;
#__PACKAGE__->meta->make_immutable;
1;