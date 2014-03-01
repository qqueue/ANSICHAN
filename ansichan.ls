require! {
  ansi
  Canvas : canvas
  request
  ent
  util
  EventSource: \eventsource
  Bacon: baconjs
  net
  #telnet
  stream
}

BOARD = process.env"BOARD" || \a

text-content = ->
  (it || '')replace /<br>/g \\n .replace /<[^>]+>/g '' |> ent.decode

wrap = (lengths, max, it) ->
  words = it.split /\n/ .map (.split /\s/)
  output = []
  row = 0
  for line in words
    current = []
    col = 0
    for word in line
      if col + 1 + word.length > (lengths[row] || max)
        output.push current.join ' '
        ++row
        while word.length > (lengths[row] || max)
          output.push word.substring 0, (lengths[row] || max)
          word.=substring (lengths[row] || max)
        current = [word]
        col = word.length + 1
      else
        current.push word
        col += 1 + word.length
    output.push current.join ' '
    ++row
  return output

function humanized bytes
  if bytes < 1024
    "#bytes B"
  else if (kbytes = Math.round bytes / 1024) < 1024
    "#kbytes KB"
  else
    "#{(kbytes / 1024)toString!substring 0 3} MB"

clip = ->
  it.substring 0 40 + if it.length > 40 then '…' else ''

!function download-img post, cb
  if post.filename?
    request.get do
      url: "http://phosphene.hakase.org/#BOARD/thumbs/
            #{post.resto || post.no}/#{post.tim}s.jpg"
      encoding: null # i.e., return body as buffer
      !(err, res, body) ->
        cb err, post <<< img: body
  else
    cb void, post

!function render cursor, img, w, h
  canvas = new Canvas w / 2, height / 2 # using half-width blocks
  ctx = canvas.get-context \2d
  ctx.draw-image img, 0 0 w, h

  data = ctx.getImageData(0, 0, w, h).data
  topBlank = false
  bottomBlank = false
  i = 0
  for x til w
    for y til h
      # in `small` mode, we have to render 2 rows at a time, where the top row
      # is the background color, and the bottom row is the foreground color
      i = ((y * w) + x) * 4
      [r, g, b, a] = data[i til i + 4]

      if alpha > 0
        cursor.bg.rgb(r, g, b);

out = new stream.PassThrough

THREAD = process.env"THREAD"

cursor = ansi out, {+enabled}

es = new EventSource "http://fountain.hakase.org/v1/#BOARD/stream/"
  ..add-event-listener \error !->
    console.error "error" it

Bacon.from-event-target es, \new-posts, (.data) >> JSON.parse
  .flat-map ->
    Bacon.from-array it.sort (a, b) -> a.no - b.no
  .filter ->
    # filter by thread if specified
    if THREAD? then (""+it.resto) is THREAD else true
  .flat-map ->
    Bacon.from-node-callback download-img, it
  .on-value (post) !->
    return unless clients > 0

    cursor.write "
    ┌──────────────────────────────────────────────────────────────────────────────┐\n
    │"
    cursor.hex \#117743 .bold!write ent.decode post.name || ''
    cursor.reset!write " #{post.now} No.#{post.no}
                         #{if post.resto is 0 then '' else "\##{post.resto}"}"
    cursor.reset!horizontal-absolute 80 .write '│\n'

    if post.filename?
      cursor.write \│
      cursor.reset!write " #{clip ent.decode post.filename + post.ext} \
                           #{post.w}x#{post.h} \
                           #{humanized post.fsize}"
      cursor.reset!horizontal-absolute 80 .write '│\n'

      img = new Canvas.Image
      img.src = post.img

      dim = if post.resto is 0 then 40 else 30

      scale = Math.min 1, dim / img.width, dim / img.height
      w = Math.floor img.width * scale
      h = Math.floor img.height * scale

      canvas = new Canvas w, h # using half-width blocks
      ctx = canvas.get-context \2d
      ctx.draw-image img, 0 0 w, h

      data = ctx.getImageData(0, 0, w, h).data
      top-blank = false
      bottom-blank = false

      margin = [w + 4 for i to h]
    else
      w = 0
      h = 0
      margin = []

    cursor.write \| .reset!horizontal-absolute 80 .write '│\n'

    com = wrap [78 - m for m in margin], 76 text-content post.com

    for y til Math.max h / 2, com.length
      cursor.write '│ '

      if post.filename? and y < (h / 2)
        for x til w
          # in `small` mode, we have to render 2 rows at a time, where the top row
          # is the background color, and the bottom row is the foreground color
          i = ((y * 2 * w) + x) * 4
          [r, g, b, a] = data[i til i + 4]

          if a > 0
            cursor.bg.rgb r, g, b
            top-blank = false
          else
            cursor.bg.reset!
            top-blank = true

          # bottom row
          # go to the next row
          i = (((y * 2 + 1) * w) + x) * 4
          [r, g, b, a] = data[i til i + 4]
          if a > 0
            cursor.fg.rgb r, g, b
            bottom-blank = false
          else
            cursor.bg.reset!
            bottom-blank = true

          if bottom-blank and not top-blank
            # swapping fg and bg for this pixel since we're gonna use a "top
            # half" instead of the usual "bottom half"
            i = ((y * 2 * w) + x) * 4
            [r, g, b, a] = data[i til i + 4]

            cursor.bg.reset!
            cursor.fg.rgb r, g, b

          cursor.write do
            if top-blank and bottom-blank
              ' '
            else if bottom-blank
              '▀'
            else
              '▄'

        cursor.reset!write ' '
      if post.filename? and y is (h / 2)
        cursor.reset!write ' ' * (margin[y] - 3)
      # text
      if y < com.length
        line = com[y]
        if line.0 is \>
          cursor.hex \#789922
          if />>\d+/.test line
            cursor.underline!hex \#dd0000
        cursor.write line

      cursor.reset!horizontal-absolute 80 .write '│\n'

    cursor.write "
    └──────────────────────────────────────────────────────────────────────────────┘\n"

clients = 0

# XXX telnet is broken
# so just use raw socket
# https://github.com/TooTallNate/node-telnet/pull/4

net.create-server (client) !->
  client.on \data !-> # ignore

  console.error "got client!"

  client.on \close !->
    console.error "client closed!"
    clients--
    out.unpipe client
    console.log "have #clients clients!"
  client.on \error !->
    console.error "client errored!" it
    clients--
    out.unpipe client
    console.log "have #clients clients!"

  out.pipe client

  clients++
  console.log "have #clients clients!"

  client.write "Welcome to ansichan!\n"
.listen process.env"PORT" || 4751


