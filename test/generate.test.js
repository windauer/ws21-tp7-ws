const util = require('./util.js');
const path = require('path');
const fs = require('fs');
const tmp = require('tmp');
const chai = require('chai');
const expect = chai.expect;
const chaiResponseValidator = require('chai-openapi-response-validator');
const axios = require('axios');

const spec = path.resolve("./modules/lib/api.json");
chai.use(chaiResponseValidator(spec));

const createOptions = {
    "odd": [
        "dta"
    ],
    "uri": "http://exist-db.org/apps/dta",
    "abbrev": "dta",
    "title": "DTA",
    "template": "view.html",
    "default-view": "div",
    "index": "tei:div",
    "owner": "tei-demo",
    "password": "demo"
};

describe('/api/generate [authenticated]', function () {

    before(util.login);

    it('generates new application', async function () {
        this.timeout(30000);
        const res = await util.axios.post('apps/generate', createOptions);
        expect(res.status).to.equal(200);
        expect(res.data.target).to.equal('/db/apps/dta');
        expect(res).to.satisfyApiSpec;
    });

    it('has new application installed', async function() {
        const query = `
            declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
            declare option output:method "json";
            declare option output:media-type "application/json";
            array { repo:list() }
        `;
        const res = await axios.get(`http://localhost:8080/exist/rest/db?_query=${encodeURIComponent(query)}&_wrap=no`);
        expect(res.status).to.equal(200);
        expect(res.data).to.include('http://exist-db.org/apps/dta');
    });

    it('downloads application xar', async function () {
        const res = await util.axios.get('apps/download/dta', {
            responseType: 'stream'
        });

        expect(res.status).to.equal(200);
        expect(res.headers['content-type']).to.equal('media-type=application/zip');

        const tempFile = tmp.tmpNameSync();
        console.log(tempFile);
        res.data.pipe(fs.createWriteStream(tempFile));
        res.data.on('end', function () {
            const stats = fs.statSync(tempFile);
            expect(stats.size).to.be.greaterThan(0);
        });
    });

    it('uninstalls application', async function () {
        const query = `
            repo:undeploy('http://exist-db.org/apps/dta'),
            repo:remove('http://exist-db.org/apps/dta')
        `;
        const res = await axios.get(`http://localhost:8080/exist/rest/db?_query=${encodeURIComponent(query)}&_wrap=no`, {
            auth: {
                "username": "admin"
            }
        });
        expect(res.status).to.equal(200);
        expect(res.data).to.match(/result="ok"/);
    });

    after(util.logout);
});

describe('/api/generate [not authenticated]', function () {
    it('should fail to generate new application', function(done) {
        this.timeout(30000);
        util.axios.post('apps/generate', createOptions)
        .catch((error) => {
            expect(error.response.status).to.equal(500);
            expect(error.response).to.satisfyApiSpec;
            done();
        })
    });
});