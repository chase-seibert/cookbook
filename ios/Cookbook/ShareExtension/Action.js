var ExtensionPreprocessingJS = function() {};

function utf8ByteLength(value) {
  var bytes = 0;
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i);
    if (code < 0x80) bytes += 1;
    else if (code < 0x800) bytes += 2;
    else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length) {
      var next = value.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        bytes += 4;
        i++;
      } else {
        bytes += 3;
      }
    } else bytes += 3;
  }
  return bytes;
}

ExtensionPreprocessingJS.prototype = {
  run: function(arguments) {
    var maxCharacters = 160000;
    var maxUTF8Bytes = 160000;
    var title = (document.title || "").slice(0, 2000);
    var url = document.location.href;
    var recipe = null;
    var scripts = document.querySelectorAll('script[type="application/ld+json"]');
    for (var i = 0; i < scripts.length && !recipe; i++) {
      try {
        var parsed = JSON.parse(scripts[i].textContent || "null");
        var queue = Array.isArray(parsed) ? parsed.slice() : [parsed];
        while (queue.length && !recipe) {
          var value = queue.shift();
          if (!value || typeof value !== "object") continue;
          var types = Array.isArray(value["@type"]) ? value["@type"] : [value["@type"]];
          if (types.indexOf("Recipe") >= 0) recipe = value;
          if (Array.isArray(value["@graph"])) queue = queue.concat(value["@graph"]);
        }
      } catch (_) {}
    }
    var text = recipe ? JSON.stringify(recipe) + "\n\n" + (document.body ? document.body.innerText : "") : (document.body ? document.body.innerText : "");
    var image = recipe && recipe.image ? recipe.image : null;
    if (Array.isArray(image)) image = image[0];
    if (image && typeof image === "object") image = image.url || image.contentUrl || null;
    if (typeof image !== "string" || !image) {
      var ogImage = document.querySelector('meta[property="og:image"], meta[name="twitter:image"]');
      image = ogImage ? ogImage.content : null;
    }
    if (!image) {
      var candidates = Array.prototype.slice.call(document.images || []).filter(function(img) {
        return img.currentSrc && img.naturalWidth >= 240 && img.naturalHeight >= 160;
      }).sort(function(a, b) { return (b.naturalWidth * b.naturalHeight) - (a.naturalWidth * a.naturalHeight); });
      image = candidates.length ? candidates[0].currentSrc : null;
    }
    try { if (image) image = new URL(image, document.location.href).href; } catch (_) { image = null; }
    text = text.slice(0, maxCharacters);
    while (utf8ByteLength(text) > maxUTF8Bytes) text = text.slice(0, Math.floor(text.length * 0.9));
    arguments.completionFunction({"url": url, "title": title, "text": text, "imageURL": image});
  }
};

ExtensionPreprocessingJS = new ExtensionPreprocessingJS();
