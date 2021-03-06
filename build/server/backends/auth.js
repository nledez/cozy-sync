// Generated by CoffeeScript 1.10.0
var BasicAuth, Exc, WebDAVAccount;

Exc = require('cozy-jsdav-fork/lib/shared/exceptions');

BasicAuth = require('cozy-jsdav-fork/lib/DAV/plugins/auth/abstractBasic');

WebDAVAccount = require('../models/webdavaccount');

module.exports = BasicAuth.extend({
  validateUserPass: function(username, password, cbvalidpass) {
    return WebDAVAccount.first(function(err, account) {
      var result;
      result = !err && (account != null) && account.token === password;
      return cbvalidpass(result);
    });
  }
});
