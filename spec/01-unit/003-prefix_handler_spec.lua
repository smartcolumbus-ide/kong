local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local prefix_handler = require "kong.cmd.utils.prefix_handler"

local exists = helpers.path.exists
local join = helpers.path.join

describe("NGINX conf compiler", function()
  describe("gen_default_ssl_cert()", function()
    local conf = assert(conf_loader(helpers.test_conf_path, {
      prefix = "ssl_tmp",
      ssl = true,
      ssl_cert = "spec/fixtures/kong_spec.crt",
      ssl_cert_key = "spec/fixtures/kong_spec.key",
      admin_ssl = true,
      admin_ssl_cert = "spec/fixtures/kong_spec.crt",
      admin_ssl_cert_key = "spec/fixtures/kong_spec.key",
    }))
    before_each(function()
      helpers.dir.makepath("ssl_tmp")
    end)
    after_each(function()
      pcall(helpers.dir.rmtree, "ssl_tmp")
    end)
    describe("proxy", function()
      it("auto-generates SSL certificate and key", function()
        assert(prefix_handler.gen_default_ssl_cert(conf))
        assert(exists(conf.ssl_cert_default))
        assert(exists(conf.ssl_cert_key_default))
      end)
      it("does not re-generate if they already exist", function()
        assert(prefix_handler.gen_default_ssl_cert(conf))
        local cer = helpers.file.read(conf.ssl_cert_default)
        local key = helpers.file.read(conf.ssl_cert_key_default)
        assert(prefix_handler.gen_default_ssl_cert(conf))
        assert.equal(cer, helpers.file.read(conf.ssl_cert_default))
        assert.equal(key, helpers.file.read(conf.ssl_cert_key_default))
      end)
    end)
    describe("admin", function()
      it("auto-generates SSL certificate and key", function()
        assert(prefix_handler.gen_default_ssl_cert(conf, true))
        assert(exists(conf.admin_ssl_cert_default))
        assert(exists(conf.admin_ssl_cert_key_default))
      end)
      it("does not re-generate if they already exist", function()
        assert(prefix_handler.gen_default_ssl_cert(conf, true))
        local cer = helpers.file.read(conf.admin_ssl_cert_default)
        local key = helpers.file.read(conf.admin_ssl_cert_key_default)
        assert(prefix_handler.gen_default_ssl_cert(conf, true))
        assert.equal(cer, helpers.file.read(conf.admin_ssl_cert_default))
        assert.equal(key, helpers.file.read(conf.admin_ssl_cert_key_default))
      end)
    end)
  end)

  describe("prepare_prefix()", function()
    local tmp_config = conf_loader(helpers.test_conf_path, {
      prefix = "servroot_tmp"
    })

    before_each(function()
      pcall(helpers.dir.rmtree, tmp_config.prefix)
      helpers.dir.makepath(tmp_config.prefix)
    end)
    after_each(function()
      pcall(helpers.dir.rmtree, tmp_config.prefix)
    end)

    it("creates inexistent prefix", function()
      finally(function()
        pcall(helpers.dir.rmtree, "inexistent")
      end)

      local config = assert(conf_loader(helpers.test_conf_path, {
        prefix = "inexistent"
      }))
      assert(prefix_handler.prepare_prefix(config))
      assert.truthy(exists("inexistent"))
    end)
    it("ensures prefix is a directory", function()
      local tmp = os.tmpname()
      finally(function()
        os.remove(tmp)
      end)

      local config = assert(conf_loader(helpers.test_conf_path, {
        prefix = tmp
      }))
      local ok, err = prefix_handler.prepare_prefix(config)
      assert.equal(tmp .. " is not a directory", err)
      assert.is_nil(ok)
    end)
    it("creates pids folder", function()
      assert(prefix_handler.prepare_prefix(tmp_config))
      assert.truthy(exists(join(tmp_config.prefix, "pids")))
    end)
    it("creates NGINX conf and log files", function()
      assert(prefix_handler.prepare_prefix(tmp_config))
      assert.truthy(exists(tmp_config.kong_env))
      assert.truthy(exists(tmp_config.nginx_kong_conf))
      assert.truthy(exists(tmp_config.nginx_err_logs))
      assert.truthy(exists(tmp_config.nginx_acc_logs))
      assert.truthy(exists(tmp_config.nginx_admin_acc_logs))
    end)
    it("dumps Kong conf", function()
      assert(prefix_handler.prepare_prefix(tmp_config))
      local in_prefix_kong_conf = assert(conf_loader(tmp_config.kong_env))
      assert.same(tmp_config, in_prefix_kong_conf)
    end)
    it("dump Kong conf (custom conf)", function()
      local conf = assert(conf_loader(nil, {
        pg_database = "foobar",
        prefix = tmp_config.prefix
      }))
      assert.equal("foobar", conf.pg_database)
      assert(prefix_handler.prepare_prefix(conf))
      local in_prefix_kong_conf = assert(conf_loader(tmp_config.kong_env))
      assert.same(conf, in_prefix_kong_conf)
    end)
    it("writes custom plugins in Kong conf", function()
      local conf = assert(conf_loader(nil, {
        custom_plugins = { "foo", "bar" },
        prefix = tmp_config.prefix
      }))

      assert(prefix_handler.prepare_prefix(conf))

      local in_prefix_kong_conf = assert(conf_loader(tmp_config.kong_env))
      assert.True(in_prefix_kong_conf.plugins.foo)
      assert.True(in_prefix_kong_conf.plugins.bar)
    end)

    describe("ssl", function()
      it("does not create SSL dir if disabled", function()
        local conf = conf_loader(nil, {
          prefix = tmp_config.prefix,
          ssl = false,
          admin_ssl = false
        })

        assert(prefix_handler.prepare_prefix(conf))
        assert.falsy(exists(join(conf.prefix, "ssl")))
      end)
      it("does not create SSL dir if using custom cert", function()
        local conf = conf_loader(nil, {
          prefix = tmp_config.prefix,
          ssl = true,
          ssl_cert = "spec/fixtures/kong_spec.crt",
          ssl_cert_key = "spec/fixtures/kong_spec.key",
          admin_ssl = true,
          admin_ssl_cert = "spec/fixtures/kong_spec.crt",
          admin_ssl_cert_key = "spec/fixtures/kong_spec.key",
        })

        assert(prefix_handler.prepare_prefix(conf))
        assert.falsy(exists(join(conf.prefix, "ssl")))
      end)
      it("generates default SSL cert", function()
        local conf = conf_loader(nil, {
          prefix = tmp_config.prefix,
          ssl = true,
          admin_ssl = true
        })

        assert(prefix_handler.prepare_prefix(conf))
        assert.truthy(exists(join(conf.prefix, "ssl")))
        assert.truthy(exists(conf.ssl_cert_default))
        assert.truthy(exists(conf.ssl_cert_key_default))
        assert.truthy(exists(conf.admin_ssl_cert_default))
        assert.truthy(exists(conf.admin_ssl_cert_key_default))
      end)
    end)

    describe("custom template", function()
      local templ_fixture = "spec/fixtures/custom_nginx.template"

      it("accepts a custom NGINX conf template", function()
        assert(prefix_handler.prepare_prefix(tmp_config, templ_fixture))
        assert.truthy(exists(tmp_config.nginx_conf))

        local contents = helpers.file.read(tmp_config.nginx_conf)
        assert.matches("# This is a custom nginx configuration template for Kong specs", contents, nil, true)
        assert.matches("daemon on;", contents, nil, true)
        assert.matches("listen 0.0.0.0:9000;", contents, nil, true)
      end)
      it("errors on non-existing file", function()
        local ok, err = prefix_handler.prepare_prefix(tmp_config, "spec/fixtures/inexistent.template")
        assert.is_nil(ok)
        assert.equal("no such file: spec/fixtures/inexistent.template", err)
      end)
    end)
  end)
end)

