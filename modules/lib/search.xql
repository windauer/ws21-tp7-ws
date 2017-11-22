(:
 :
 :  Copyright (C) 2015 Wolfgang Meier
 :
 :  This program is free software: you can redistribute it and/or modify
 :  it under the terms of the GNU General Public License as published by
 :  the Free Software Foundation, either version 3 of the License, or
 :  (at your option) any later version.
 :
 :  This program is distributed in the hope that it will be useful,
 :  but WITHOUT ANY WARRANTY; without even the implied warranty of
 :  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 :  GNU General Public License for more details.
 :
 :  You should have received a copy of the GNU General Public License
 :  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 :)
xquery version "3.1";

(:~
 : Template functions to handle search.
 :)
module namespace search="http://www.tei-c.org/tei-simple/search";

declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace templates="http://exist-db.org/xquery/templates";
import module namespace query="http://www.tei-c.org/tei-simple/query" at "../query.xql";
import module namespace kwic="http://exist-db.org/xquery/kwic" at "resource:org/exist/xquery/lib/kwic.xql";
import module namespace pages="http://www.tei-c.org/tei-simple/pages" at "pages.xql";
import module namespace tpu="http://www.tei-c.org/tei-publisher/util" at "util.xql";
import module namespace nav="http://www.tei-c.org/tei-simple/navigation" at "../navigation.xql";
import module namespace browse="http://www.tei-c.org/tei-simple/templates" at "browse.xql";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";
import module namespace console="http://exist-db.org/xquery/console" at "java:org.exist.console.xquery.ConsoleModule";

(:~
: Execute the query. The search results are not output immediately. Instead they
: are passed to nested templates through the $model parameter.
:
: @author Wolfgang M. Meier
: @author Jens Østergaard Petersen
: @param $node
: @param $model
: @param $query The query string. This string is transformed into a <query> element containing one or two <bool> elements in a Lucene query and it is transformed into a sequence of one or two query strings in an ngram query. The first <bool> and the first string contain the query as input and the second the query as transliterated into Devanagari or IAST as determined by $query-scripts. One <bool> and one query string may be empty.
: @param $tei-target A sequence of one or more targets within a TEI document, the tei:teiHeader or tei:text.
: @param $target-texts A sequence of the string "all" or of the xml:ids of the documents selected.

: @return The function returns a map containing the $hits and the $query. The search results are output through the nested templates, browse:hit-count, browse:paginate, and browse:show-hits.
:)
declare
    %templates:default("tei-target", "tei-text")
function search:query($node as node()*, $model as map(*), $query as xs:string?, $tei-target as xs:string+, $doc as xs:string*) as map(*) {
        (:If there is no query string, fill up the map with existing values:)
        if (empty($query))
        then
            map {
                "hits" : session:get-attribute("apps.simple"),
                "hitCount" : session:get-attribute("apps.simple.hitCount"),
                "query" : session:get-attribute("apps.simple.query"),
                "docs" : session:get-attribute("apps.simple.docs")
            }
        else
            (:Otherwise, perform the query.:)
            (: Here the actual query commences. This is split into two parts, the first for a Lucene query and the second for an ngram query. :)
            (:The query passed to a Luecene query in ft:query is an XML element <query> containing one or two <bool>. The <bool> contain the original query and the transliterated query, as indicated by the user in $query-scripts.:)
            let $hits :=
                    (:If the $query-scope is narrow, query the elements immediately below the lowest div in tei:text and the four major element below tei:teiHeader.:)
                    for $hit in query:query-default($tei-target, $query, $doc)
                    order by ft:score($hit) descending
                    return $hit
            let $hitCount := count($hits)
            let $hits := if ($hitCount > 1000) then subsequence($hits, 1, 1000) else $hits
            (:Store the result in the session.:)
            let $store := (
                session:set-attribute("apps.simple", $hits),
                session:set-attribute("apps.simple.hitCount", $hitCount),
                session:set-attribute("apps.simple.query", $query),
                session:set-attribute("apps.simple.docs", $doc)
            )
            return
                (: The hits are not returned directly, but processed by the nested templates :)
                map {
                    "hits" : $hits,
                    "hitCount" : $hitCount,
                    "query" : $query,
                    "docs": $doc
                }
};

declare function search:form-current-doc($node as node(), $model as map(*), $doc as xs:string?) {
    <input type="hidden" name="doc" value="{$doc}"/>
};

(:~
    Output the actual search result as a div, using the kwic module to summarize full text matches.
:)
declare
    %templates:wrap
    %templates:default("start", 1)
    %templates:default("per-page", 10)
function search:show-hits($node as node()*, $model as map(*), $start as xs:integer, $per-page as xs:integer, $view as xs:string?) {
    for $hit at $p in subsequence($model("hits"), $start, $per-page)
    let $config := tpu:parse-pi(root($hit), $view)
    let $parent := query:get-parent-section($config, $hit)
    let $parent-id := config:get-identifier($parent)
    let $parent-id := if ($model?docs) then replace($parent-id, "^.*?([^/]*)$", "$1") else $parent-id
    let $div := query:get-current($config, $parent)
    let $loc :=
        <tr class="reference">
            <td colspan="3">
                <span class="number">{$start + $p - 1}</span>
                { query:get-breadcrumbs($config, $hit, $parent-id) }
            </td>
        </tr>
    let $expanded := util:expand($hit, "add-exist-id=all")
    let $docId := config:get-identifier($div)
    return (
        $loc,
        for $match in subsequence($expanded//exist:match, 1, 5)
        let $matchId := $match/../@exist:id
        let $docLink :=
            if ($config?view = "page") then
                let $contextNode := util:node-by-id($div, $matchId)
                let $page := $contextNode/preceding::tei:pb[1]
                return
                    if ($page) then
                        util:node-id($page)
                    else
                        util:node-id($div)
            else
                util:node-id($div)
        let $config := <config width="60" table="yes" link="{$docId}?root={$docLink}&amp;action=search&amp;view={$config?view}&amp;odd={$config?odd}#{$matchId}"/>
        return
            kwic:get-summary($expanded, $match, $config)
    )
};
