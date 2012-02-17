package RapidApp::AppTree;
use Moose;
extends 'RapidApp::AppCmp';

use RapidApp::Include qw(sugar perlutil);


has 'add_button_text' => ( is => 'ro', isa => 'Str', default => 'Add' );
has 'add_button_iconCls' => ( is => 'ro', isa => 'Str', default => 'icon-add' );
has 'delete_button_text' => ( is => 'ro', isa => 'Str', default => 'Delete' );
has 'delete_button_iconCls' => ( is => 'ro', isa => 'Str', default => 'icon-delete' );

has 'use_contextmenu' => ( is => 'ro', isa => 'Bool', default => 0 );
has 'no_dragdrop_menu' => ( is => 'ro', isa => 'Bool', default => 0 );
has 'setup_tbar' => ( is => 'ro', isa => 'Bool', default => 0 );
has 'no_recursive_delete' => ( is => 'ro', isa => 'Bool', default => 1 );

#Controls if nodes can drag/drop between nodes as well as into (append) nodes
has 'ddAppendOnly' => ( is => 'ro', isa => 'Bool', default => 1 );

has 'extra_node_actions' => ( is => 'ro', isa => 'Maybe[ArrayRef]', lazy => 1, default => undef );

sub BUILD {
	my $self = shift;
	$self->apply_extconfig(
		xtype						=> 'apptree',
		border					=> \0,
		layout					=> 'fit',
		containerScroll 		=> \1,
		autoScroll				=> \1,
		animate					=> \1,
		useArrows				=> \1,
		use_contextmenu		=> jstrue($self->use_contextmenu) ? \1 : \0,
		no_dragdrop_menu		=> jstrue($self->no_dragdrop_menu) ? \1 : \0,
		setup_tbar				=> jstrue($self->setup_tbar) ? \1 : \0,
		no_recursive_delete	=> jstrue($self->no_recursive_delete) ? \1 : \0,
		ddAppendOnly			=> jstrue($self->ddAppendOnly) ? \1 : \0,
	);
	
	$self->apply_extconfig( extra_node_actions => $self->extra_node_actions ) if ($self->extra_node_actions);
	
	$self->apply_extconfig(
		add_node_text 			=> $self->add_button_text,
		add_node_iconCls		=> $self->add_button_iconCls,
		delete_node_text		=> $self->delete_button_text,
		delete_node_iconCls	=> $self->delete_button_iconCls
	);
	
	$self->apply_actions( nodes 	=> 'call_fetch_nodes' );
	$self->apply_actions( node 	=> 'call_fetch_node' ) if ($self->can('fetch_node'));
	
	if($self->can('add_node')) {
		$self->apply_actions( add 	=> 'call_add_node' );
		$self->apply_extconfig( add_node_url => $self->suburl('add') );
	}
	
	if($self->can('delete_node')) {
		$self->apply_actions( delete 	=> 'call_delete_node' ); 
		$self->apply_extconfig( delete_node_url => $self->suburl('delete') );
	}
	
	if($self->can('rename_node')) {
		$self->apply_actions( rename 	=> 'call_rename_node' );
		$self->apply_extconfig( rename_node_url => $self->suburl('rename') );
	}
	
	if($self->can('copy_node')) {
		$self->apply_actions( copy => 'call_copy_node' );
		$self->apply_extconfig( copy_node_url => $self->suburl('copy') );
	}
	
	if($self->can('move_node')) {
		$self->apply_actions( move => 'call_move_node' );
		$self->apply_extconfig( move_node_url => $self->suburl('move') );
	}
	
	$self->add_ONREQUEST_calls('init_onreq');
}


sub init_onreq {
	my $self = shift;
	
	$self->apply_extconfig(
		id						=> $self->instance_id,
		dataUrl				=> $self->suburl('/nodes'),
		rootVisible			=> $self->show_root_node ? \1 : \0,
		root					=> $self->root_node,
		tbar					=> $self->tbar,
	);
	
	my $node = $self->init_jump_to_node or return;

	$self->add_listener( 
		afterrender => RapidApp::JSONFunc->new( raw => 1, func => 
			'function(tree) {' .
				'Ext.ux.RapidApp.AppTree.jump_to_node_id(tree,"' . $node . '");' .
			'}'
		)
	);
}


sub init_jump_to_node {
	my $self = shift;
	
	my $node;
	$node = $self->root_node_name if ($self->show_root_node);
	$node = $self->c->req->params->{node} if ($self->c->req->params->{node});
	
	return $node;
}

# If set to true, child nodes are automatically fetched recursively:
has 'fetch_nodes_deep', is => 'ro', isa => 'Bool', default => 0;

# Auto-sets 'expanded' on nodes with child nodes (only applies to children nodes
# loaded within 'call_fetch_nodes' because of 'fetch_nodes_deep' being set to true)
has 'default_expanded', is => 'ro', isa => 'Bool', default => 0;


##
##
## fetch_nodes(node_path) [Required]
##		method to fetch the tree dataUrl, first argument is the node path
has 'fetch_nodes'		=> ( is => 'ro', default => sub { return []; } );
##


##
## show_root_node
##		whether or not to show the root node
has 'show_root_node'		=> ( is => 'ro', default => 0 );
##

##
## root_node_name
##		Name of the root node (default 'root')
has 'root_node_name'		=> ( is => 'ro', default => 'root' );
##


##
## root_node_text
##		text of the root node
has 'root_node_text'		=> ( is => 'ro', lazy => 1, default => sub { (shift)->root_node_name; } );
##

##
## add_nodes: define as a method to support adding to the tree
##


sub call_fetch_nodes {
	my $self = shift;
	my $node = shift || $self->c->req->params->{node};
	
	my $nodes = $self->fetch_nodes($node);
	
	die "Error: 'fetch_nodes()' was supposed to return an ArrayRef, but instead if returned: " . Dumper($nodes)
		unless (ref($nodes) eq 'ARRAY');
	
	my %seen_id = ();
	
	foreach my $n (@$nodes) {
		if (jstrue($n->{leaf}) or (exists $n->{allowChildren} and ! jstrue($n->{allowChildren}))) {
			$n->{loaded} = \1 unless (exists $n->{loaded});
			next;
		}
		
		# Each sub-node definition should contain 'id' - its node path. But if it doesn't, 
		# just leave it as-is:
		next unless (exists $n->{id});
		
		## If we've gotten this far, it means the current node can contain child nodes
		
		die "Invalid node definition: id can't be the same as the parent node ($node): " . Dumper($n) 
			if($n->{id} eq $node);
			
		die "Invalid node definition: duplicate id ($n->{id}): " . Dumper($n)
			if($seen_id{$n->{id}}++);
		
		# The id should be a fully qualified '/' delim path prefixed with the (parent) node 
		# path ($node supplied to this function). If it is not, assume it is a relative path 
		# and prefix it automatically:
		$n->{id} = $node . '/' . $n->{id} unless ($n->{id} =~ /^${node}/);
		
		# This is (imo) an ExtJS bug. It fixes the problem where empty nodes are automatically
		# made "leaf" nodes and get a stupid, non-folder default icon
		# http://www.sencha.com/forum/showthread.php?92553-Async-tree-make-empty-nodes-appear-as-quot-nodes-quot-not-quot-leaves-quot&p=441294&viewfull=1#post441294
		$n->{cls} = 'x-tree-node-collapsed' unless (exists $n->{cls});
		
		# legacy:
		$n->{expanded} = \1 if ($n->{expand} and ! exists $n->{expanded});
		
		# Pre-fetch child nodes automatically if 'fetch_nodes_deep' is set to true:
		if($self->fetch_nodes_deep and ! exists $n->{children}) {
			my $children = $self->call_fetch_nodes($n->{id});
			if(@$children > 0) {
				$n->{children} = $children;
				$n->{expanded} = \1 if ($self->default_expanded and ! exists $n->{expanded});
			}
			else {
				# Set loaded to true if this node is empty (prevents being initialized with a +/- toggle):
				$n->{loaded} = \1 unless (exists $n->{loaded});
			}
		}
		
		# WARNING: note that setting 'children' of a node to an empty array will prevent subsequent
		# ajax loading of the node's children (should any exist later)
	}
	
	return $nodes;
}

sub call_fetch_node {
	my $self = shift;
	my $node = $self->c->req->params->{node};
	return $self->fetch_node($node);
}

sub call_add_node {
	my $self = shift;
	my $name = $self->c->req->params->{name};
	my $node = $self->c->req->params->{node};
	return $self->add_node($name,$node);
}

sub call_delete_node {
	my $self = shift;
	my $name = $self->c->req->params->{name};
	my $node = $self->c->req->params->{node};
	my $recursive = $self->c->req->params->{recursive};
	return $self->delete_node($node,$recursive);
}

sub call_rename_node {
	my $self = shift;
	my $name = $self->c->req->params->{name};
	my $node = $self->c->req->params->{node};
	return $self->rename_node($node,$name);
}

sub call_copy_node {
	my $self = shift;
	my $node = $self->c->req->params->{node};
	my $target = $self->c->req->params->{target};
	
	# point and point_node will be defined for positional information, if
	# a node is dragged in-between 2 nodes (point above/below instead of append)
	# point_node is undef if point is append
	my $point_node = $self->c->req->params->{point_node};
	my $point = $self->c->req->params->{point};
	
	return $self->copy_node($node,$target,$point,$point_node);
}

sub call_move_node {
	my $self = shift;
	my $node = $self->c->req->params->{node};
	my $target = $self->c->req->params->{target};
	
	# point and point_node will be defined for positional information, if
	# a node is dragged in-between 2 nodes (point above/below instead of append)
	# point_node is undef if point is append
	my $point_node = $self->c->req->params->{point_node};
	my $point = $self->c->req->params->{point};
	
	return $self->move_node($node,$target,$point,$point_node);
}


has 'root_node' => ( is => 'ro', lazy => 1, default => sub {
	my $self = shift;
	return {
		nodeType		=> 'async',
		id				=> $self->root_node_name,
		text			=> $self->root_node_text,
		draggable	=> \0
	};
});


has 'tbar' => ( is => 'ro', lazy => 1, default => sub {
	my $self = shift;
	return undef;
	return ['->'];
	
	my $tbar = [];

	push @$tbar, $self->delete_button if ($self->can('delete_node'));
	push @$tbar, $self->add_button if ($self->can('add_node'));

	return undef unless (scalar @$tbar > 0);

	unshift @$tbar, '->';

	return $tbar;
});






sub add_button {
	my $self = shift;
	
	return RapidApp::JSONFunc->new(
		func => 'new Ext.Button', 
		parm => {
			text 		=> $self->add_button_text,
			iconCls	=> $self->add_button_iconCls,
			handler 	=> RapidApp::JSONFunc->new( 
				raw => 1, 
				func => 'function(btn) { ' . 
					'var tree = btn.ownerCt.ownerCt;'.
					'tree.nodeAdd();' .
					#'tree.nodeAdd(tree.activeNonLeafNode());' .				
				'}'
			)
	});
}


sub delete_button {
	my $self = shift;
	
	return RapidApp::JSONFunc->new(
		func => 'new Ext.Button', 
		parm => {
			tooltip		=> $self->delete_button_text,
			iconCls	=> $self->delete_button_iconCls,
			handler 	=> RapidApp::JSONFunc->new( 
				raw => 1, 
				func => 'function(btn) { ' . 
					'var tree = btn.ownerCt.ownerCt;'.
					'tree.nodeDelete(tree.getSelectionModel().getSelectedNode());' .
					#'Ext.ux.RapidApp.AppTree.del(tree,"' . $self->suburl('/delete') . '");' .
					
				'}'
			)
	});
}




#### --------------------- ####


#no Moose;
#__PACKAGE__->meta->make_immutable;
1;