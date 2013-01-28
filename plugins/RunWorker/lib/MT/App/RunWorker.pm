package MT::App::RunWorker;
use strict;
use base qw( MT::App );

sub init_request {
    my $app = shift;
    $app->SUPER::init_request(@_);
    $app->{ requires_login } = 1;
    $app;
}

sub _worker {
    my $app = shift;
    return $app->trans_error( 'Permission denied.' )
                            unless $app->user->is_superuser;
    return $app->trans_error( 'Permission denied.' )
                            unless $app->validate_magic;
    my $daemonize = 0;
    my $sleep     = 5;
    my $help      = 0;
    my $load      = 10;
    my $verbose   = 0;
    my $scoreboard;
    my $randomize_jobs = 0;
    my $trace_objects  = 0;
    require MT::TheSchwartz;
    if ( $trace_objects ) {
        require Devel::Leak::Object;
        Devel::Leak::Object->import(qw{ GLOBAL_bless });
    }
    my $proc_process_table = eval {
        require Proc::ProcessTable;
        1;
    };
    $@ = undef;
    my %cfg;
    $cfg{ verbose }    = $verbose;
    $cfg{ scoreboard } = $scoreboard;
    $cfg{ prioritize } = 1;
    $cfg{ randomize }  = $randomize_jobs;
    require MT::Bootstrap;
    require MT;
    my $mt = MT->new() or die MT->errstr;
    if ( defined( MT->config( 'RPTProcessCap' ) ) && $proc_process_table ) {
        my $t = new Proc::ProcessTable;
        my $rpt_count;
        foreach my $p ( @{ $t->table } ) {
            my $cmd = $p->cmndline;
            if ( ( $cmd =~ /^perl/ && $cmd =~ /run-workers/ ) || 
                 ( $cmd =~ /^perl/ && $cmd =~ /run-tasks/ ) ||
                 ( $cmd =~ /^perl/ && $cmd =~ /run-periodic-tasks/ ) ) {
                $rpt_count += 1;
            }
        }
        if ( $rpt_count > MT->config( 'RPTProcessCap' ) ) {
            $rpt_count = $rpt_count - 1;
            return "$rpt_count processes already running; cancelling rebuild_queue launch\n";
        }
    }
    if ( MT->config( 'RPTFreeMemoryLimit' ) ) {
        my $limit = MT->config( 'RPTFreeMemoryLimit' );
        if ( $limit and ! MT::TheSchwartz::_has_enough_swap( $limit ) ) {
            return
                "Free memory below RPT limit; cancelling rebuild_queue launch\n";
        }
    }
    if ( MT->config( 'RPTFreeSwapLimit' ) ) {
        my $swaplimit = MT->config( 'RPTSwapMemoryLimit' );
        if ( $swaplimit and ! MT::TheSchwartz::_has_enough_swap( $swaplimit ) ) {
            return
                "Free swap memory below RPT limit; cancelling rebuild_queue launch\n";
        }
    }
    $mt->{ vtbl }                 = {};
    $mt->{ is_admin }             = 0;
    $mt->{ template_dir }         = 'cms';
    $mt->{ user_class }           = 'MT::Author';
    $mt->{ plugin_template_path } = 'tmpl';
    $mt->run_callbacks( 'init_app', $mt );
    my $client = eval {
        require MT::TheSchwartz;
        my $schwartz = MT::TheSchwartz->new( %cfg );
        no warnings 'once';
        $TheSchwartz::FIND_JOB_BATCH_SIZE = $load;
        $schwartz;
    };
    if ( ( my $error = $@ ) && $verbose ) {
        return "Error initializing TheSchwartz: $error\n";
    }
    if ( $daemonize && $client ) {
        $client->work_periodically( $sleep );
    } else {
        $client->work_until_done if $client;
    }
    my $admin_script = MT->config( 'AdminScript' );
    my $admin_path = MT->config( 'AdminCGIPath' );
    my $query_str = $app->uri_params( mode => 'start_worker',
                                      args => { done => 1 } );
    $app->redirect( $admin_path . $admin_script . $query_str );
    return 1;
}

1;