// Generated by CoffeeScript 1.10.0
var CozyInstance, Event, WebDAVAccount, async, fs, getTemplateName, localizationManager, log, path;

fs = require('fs');

path = require('path');

async = require('async');

WebDAVAccount = require('../models/webdavaccount');

CozyInstance = require('../models/cozyinstance');

Event = require('../models/event');

localizationManager = require('../helpers/localization_manager');

log = require('printit')({
  prefix: 'account:controller'
});

getTemplateName = function(locale) {
  var extension, fileName, filePath, runFromBuild;
  filePath = path.resolve(__dirname, '../views/index.js');
  runFromBuild = fs.existsSync(filePath);
  extension = runFromBuild ? 'js' : 'jade';
  fileName = "index." + extension;
  filePath = path.resolve(__dirname, "../views/" + fileName);
  if (!fs.existsSync(filePath)) {
    fileName = "index." + extension;
  }
  return fileName;
};

module.exports = {
  index: function(req, res) {
    return async.parallel({
      davAccount: function(done) {
        return WebDAVAccount.first(done);
      },
      calendarTags: function(done) {
        return Event.calendars(done);
      },
      instance: function(done) {
        return CozyInstance.first(done);
      }
    }, function(err, results) {
      var calendarNames, calendarTags, davAccount, domain, instance, locale;
      if (err != null) {
        log.error(err);
      }
      davAccount = results.davAccount, calendarTags = results.calendarTags, instance = results.instance;
      calendarNames = calendarTags != null ? calendarTags.map(function(calendar) {
        return calendar.name;
      }) : void 0;
      locale = (instance != null ? instance.locale : void 0) || 'en';
      domain = (instance != null ? instance.domain : void 0) || '';
      return localizationManager.ensureReady(function(err) {
        var data, fileName;
        data = {
          login: davAccount != null ? davAccount.login : void 0,
          token: davAccount != null ? davAccount.token : void 0,
          domain: domain,
          calendars: calendarNames,
          webdav: localizationManager.t('webdav'),
          standard: localizationManager.t('standard protocol'),
          tutorials: localizationManager.t('two tutorials'),
          contactsTutorial: localizationManager.t('contacts tutorial'),
          server: localizationManager.t('server credentials'),
          further: localizationManager.t('before going further'),
          log: localizationManager.t('login'),
          password: localizationManager.t('password'),
          show: localizationManager.t('show'),
          hide: localizationManager.t('hide'),
          reset: localizationManager.t('reset password'),
          dom: localizationManager.t('domain'),
          calendarTutorial: localizationManager.t('calendar'),
          client: localizationManager.t('your client will ask for'),
          serverField: localizationManager.t('in the server field'),
          android: localizationManager.t('sync android'),
          select: localizationManager.t('select a calendar'),
          url: localizationManager.t('use the following url'),
          contacts: localizationManager.t('contacts'),
          thunderbird: localizationManager.t('sync thunderbird'),
          files: localizationManager.t('WebDAV configuration (Files)'),
          file: localizationManager.t('doesn\'t support file'),
          troubleshouting: localizationManager.t('troubleshooting'),
          problems: localizationManager.t('experimenting problems'),
          github: localizationManager.t('on github')
        };
        fileName = getTemplateName(locale);
        return res.render(fileName, data);
      });
    });
  },
  createCredentials: function(req, res) {
    return WebDAVAccount.createAccount(function(err, account) {
      if (err != null) {
        return res.send(500, {
          error: err.toString()
        });
      } else {
        return res.send(201, {
          success: true,
          account: account.toJSON()
        });
      }
    });
  }
};
