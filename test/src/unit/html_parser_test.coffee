module "Trix.HTMLParser"

eachFixture (name, {html, document}) ->
  test name, ->
    parsedDocument = Trix.HTMLParser.parse(html).getDocument()
    expectHTML parsedDocument.copyUsingObjectsFromDocument(document), html

test "parses unfamiliar html", ->
  html = """<meta charset="UTF-8"><span style="font-style: italic">abc</span><span>d</span><section style="margin:0"><blink>123</blink><a href="http://example.com">45<b>6</b></a>x<br />y</section><p style="margin:0">9</p>"""
  expectedHTML = """<div><!--block--><em>abc</em>d</div><div><!--block-->123<a href="http://example.com">45<strong>6</strong></a>x<br>y</div><div><!--block-->9</div>"""
  expectHTML Trix.HTMLParser.parse(html).getDocument(), expectedHTML

test "translates block element margins to newlines", ->
  html = """<p style="margin: 0 0 1em 0">a</p><p style="margin: 0">b</p><article style="margin: 1em 0 0 0">c</article>"""
  expectedHTML = """<div><!--block-->a<br><br></div><div><!--block-->b</div><div><!--block--><br>c</div>"""
  document = Trix.HTMLParser.parse(html).getDocument()
  expectHTML document, expectedHTML

asyncTest "sanitizes unsafe html", ->
  window.unsanitized = []
  Trix.HTMLParser.parse """
    <img onload="window.unsanitized.push('img.onload');" src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACwAAAAAAQABAAACAkQBADs=">
    <img onerror="window.unsanitized.push('img.onerror');" src="data:image/gif;base64,TOTALLYBOGUS">
    <script>
      window.unsanitized.push('script tag');
    </script>
  """
  after 20, ->
    deepEqual window.unsanitized, []
    delete window.unsanitized
    QUnit.start()
