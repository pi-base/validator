import * as React from 'react'
import { connect } from 'react-redux'
import { useState } from 'react'

import { Dispatch } from '../types'
import { State } from '../reducers'
import * as A from '../actions'

type StateProps = {
  server: string
}

type DispatchProps = {
  clearCache: () => void
  changeServer: (host: string) => void
}

type Props = StateProps & DispatchProps

type CState = {
  host: string
}

class Footer extends React.Component<Props, CState> {
  constructor(props: Props) {
    super(props)
    this.state = { host: props.server }
  }

  render() {
    const { server, clearCache, changeServer } = this.props

    return (
      <nav className="navbar navbar-inverse navbar-fixed-bottom">
        <div className="container">
          <ul className="nav navbar-nav">
            <li><a href="#" onClick={clearCache}>Clear Cache</a></li>
          </ul>
          <form className="navbar-form navbar-right">
            <div className="form-group">
              <input
                className="form-control"
                placeholder={server}
                value={this.state.host}
                onChange={e => this.setState({ host: e.target.value })}
              />
            </div>
            <button
              className="btn btn-default"
              disabled={!this.state.host || this.state.host === server}
              onClick={() => changeServer(this.state.host)}
            >
              Update
            </button>
          </form>
        </div>
      </nav>
    )

  }
}

const mapStateToProps = (state: State): StateProps => ({
  server: state.client.host
})

const mapDispatchToProps = (dispatch: Dispatch): DispatchProps => ({
  clearCache: () =>
    dispatch(A.clearCache()).
      then(_ => window.location.pathname = '/'),
  changeServer: host =>
    dispatch(A.changeServer(host)).
      then(_ => window.location.pathname = '/')
})

export default connect(
  mapStateToProps,
  mapDispatchToProps
)(Footer)
