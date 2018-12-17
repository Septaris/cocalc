# 3rd Party Libraries
{Alert, Button} = require('react-bootstrap')

# Internal & React Libraries
{React, rclass, rtypes} = require('./app-framework')
{Icon} = require('./r_misc')
misc = require('smc-util/misc')

# alert style, and derived oom alert style. we want to make sure we do not change one of them accidentally...
alert_style = Object.freeze(
    marginBottom : 0
    fontSize     : '13pt'
)

oom_alert_style = Object.freeze(Object.assign({}, alert_style, {fontSize : '11pt', padding : '5px'}))


exports.DiskSpaceWarning = rclass ({name}) ->
    displayName : 'DiskSpaceWarning'

    reduxProps :
        projects :
            project_map              : rtypes.immutable.Map
            get_total_project_quotas : rtypes.func

    propTypes :
        project_id : rtypes.string

    shouldComponentUpdate: (nextProps) ->
        return @props.project_map?.get(@props.project_id) != nextProps.project_map?.get(nextProps.project_id)

    render: ->
        if not require('./customize').commercial
            return null
        quotas = @props.get_total_project_quotas(@props.project_id)
        project_status = @props.project_map?.get(@props.project_id)?.get('status')
        if not quotas?.disk_quota? or not project_status?
            return null
        else
            disk = Math.ceil(project_status.get('disk_MB') ? 0)
        if quotas.disk_quota - 5 > disk
            return null

        <Alert bsStyle='danger' style={alert_style}>
            <Icon name='exclamation-triangle' /> WARNING: This project is running out of disk space. Please increase the quota in <a onClick={=>@actions(project_id: @props.project_id).set_active_tab('settings')} style={cursor:'pointer'}>settings</a> or delete some files.
        </Alert>


exports.RamWarning = rclass ({name}) ->
    displayName : 'RAMWarning'

    reduxProps :
        projects :
            project_map              : rtypes.immutable.Map
            get_total_project_quotas : rtypes.func

    propTypes :
        project_id : rtypes.string

    shouldComponentUpdate: (nextProps) ->
        return @props.project_map?.get(@props.project_id) != nextProps.project_map?.get(nextProps.project_id)

    render: ->
        if not require('./customize').commercial
            return <span />
        quotas = @props.get_total_project_quotas(@props.project_id)
        project_status = @props.project_map?.get(@props.project_id)?.get('status')
        if not quotas?.memory? or not project_status?
            return <span />
        else
            rss = project_status.get('memory')?.get('rss')
            if not rss
                return <span />
            memory = Math.round(rss/1000)
        if quotas.memory > memory + 100
            return <span />

        <Alert bsStyle='danger' style={alert_style}>
            <Icon name='exclamation-triangle' /> WARNING: This project is running low on memory.{' '}
            Upgrade Shared RAM memory in <a onClick={=>@actions(project_id: @props.project_id).set_active_tab('settings')} style={cursor:'pointer'}>settings</a>,{' '}
            restart your project or kill some processes.{' '}
            (<a href={'https://github.com/sagemathinc/cocalc/wiki/My-Project-Is-Running-Out-of-Memory'} target={'_blank'} style={cursor:'pointer'}>more information</a>; memory usage is updated about once per minute.)
        </Alert>


# to test this, set the oom_kills value for your dev project directly in the DB:
# 1. reset:         UPDATE projects SET status = jsonb_set(status, '{oom_kills}', '0'::JSONB) WHERE project_id='  ... UUID of your cc-in-cc project ... ';
# 2. single event:  UPDATE projects SET status = jsonb_set(status, '{oom_kills}', '1'::JSONB) WHERE project_id='  ... UUID of your cc-in-cc project ... ';
# 3. several more:  UPDATE projects SET status = jsonb_set(status, '{oom_kills}', '5'::JSONB) WHERE project_id='  ... UUID of your cc-in-cc project ... ';
# 4. reset:         UPDATE projects SET status = jsonb_set(status, '{oom_kills}', '0'::JSONB) WHERE project_id='  ... UUID of your cc-in-cc project ... ';
exports.OOMWarning = rclass ({name}) ->
    displayName : 'OOMWarning'

    reduxProps :
        projects :
            project_map              : rtypes.immutable.Map
        "#{name}" :
            oom_dismissed            : rtypes.number

    propTypes :
        project_id : rtypes.string

    getDefaultProps: ->
        oom_dismissed : 0

    shouldComponentUpdate: (nextProps) ->
        return @props.project_map?.get(@props.project_id) != nextProps.project_map?.get(nextProps.project_id) \
            or @props.oom_dismissed != nextProps.oom_dismissed

    click: (oom_kills) ->
        @actions(name).setState(oom_dismissed: oom_kills)

    render: ->
        if not require('./customize').commercial
            return <span />
        project = @props.project_map?.get(@props.project_id)
        project_state = project?.get('state')?.get('state')
        if project_state != 'running'
            return <span />
        project_status = project?.get('status')
        if not project_status?
            return <span />
        oom_kills = project_status.get('oom_kills') ? 0
        oom_dismissed = @props.oom_dismissed

        # if DEBUG then console.log("oom_kills: #{oom_kills}, oom_dismissed: #{oom_dismissed}")

        if oom_kills <= oom_dismissed
            return <span />

        # first time message is different from later ones
        if @props.oom_dismissed == 0
            msg = <span>WARNING: There {misc.plural(oom_kills, 'was', 'were')} {oom_kills} out-of-memory {misc.plural(oom_kills, 'situation')} in your project, because your calculations are too memory intensive.</span>
            style = 'info'
        else
            diff = oom_kills - oom_dismissed
            msg = <span>WARNING: There {misc.plural(diff, 'was', 'were')} {diff} additional out-of-memory {misc.plural(diff, 'situation')} in your project.</span>
            style = 'danger'

        <Alert bsStyle={style} style={oom_alert_style}>
            <div style={display: 'flex'}>
                <div style={flex:'1'}>
                    <Icon name='exclamation-triangle' /> {msg}{' '}
                    You either have to kill some processes, close running Jupyter Notebooks via "Halt", or restart your project.{' '}
                    Increasing "Shared RAM" memory in <a onClick={=>@actions(project_id: @props.project_id).set_active_tab('settings')} style={cursor:'pointer'}>settings</a> could help.{' '}
                    <a href={'https://github.com/sagemathinc/cocalc/wiki/My-Project-Is-Running-Out-of-Memory'} target={'_blank'} style={cursor:'pointer'}>More information...</a>.
                </div>
                <div style={flex:'0'}>
                    <Button onClick={=>@click(oom_kills)} pullright={"true"}>Dismiss</Button>
                </div>
            </div>
        </Alert>
