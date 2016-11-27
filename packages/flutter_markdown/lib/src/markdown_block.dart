// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:markdown/markdown.dart' as md;
import 'package:meta/meta.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';

import 'markdown_style_raw.dart';

typedef void MarkdownLinkCallback(String href);

class _BlockBuilder implements md.NodeVisitor {
  _BlockBuilder({
    this.syntaxHighlighter,
    this.linkHandler,
  });

  List<MarkdownBlock> createBlock(List<md.Node> nodes) {
    _blocks.clear();
    _listIndents.clear();

    for (final md.Node node in nodes)
      node.accept(this);

    return _blocks;
  }

  final List<MarkdownBlock> _blocks = <MarkdownBlock>[];
  final List<String> _listIndents = <String>[];

  final SyntaxHighlighter syntaxHighlighter;
  final _LinkHandler linkHandler;

  @override
  void visitText(md.Text text) {
    final _MarkdownInlineContainer inlineContainer = _currentBlock.inlines.last;
    final List<_MarkdownInline> inlineList = inlineContainer.children;

    if (_currentBlock.tag == 'pre')
      inlineList.add(new _MarkdownInlineTextSpan(syntaxHighlighter.format(text.text)));
    else
      inlineList.add(new _MarkdownInlineString(text.text));
  }

  @override
  bool visitElementBefore(md.Element element) {
    if (_isListTag(element.tag))
      _listIndents.add(element.tag);

    if (_isBlockTag(element.tag)) {
      final List<MarkdownBlock> blockList = _currentBlock == null ? _blocks : _currentBlock.children;
      blockList.add(new MarkdownBlock(
        tag: element.tag,
        attributes: element.attributes,
        listIndents: new List<String>.from(_listIndents),
        listIndex: blockList.length,
      ));
    } else {
      _LinkInfo linkInfo;

      if (element.tag == 'a')
        linkInfo = linkHandler.createLinkInfo(element.attributes['href']);

      TextStyle textStyle = style.styles[element.tag] ?? const TextStyle();
      List<_MarkdownInline> styleElement = <_MarkdownInline>[new _MarkdownInlineTextStyle(textStyle, linkInfo)];
      _currentBlock.inlines.add(new _MarkdownInlineContainer(styleElement));
    }
    return true;
  }

  @override
  void visitElementAfter(md.Element element) {
    if (_isListTag(element.tag))
      _listIndents.removeLast();

    if (_isBlockTag(element.tag)) {
      if (_currentBlock.inlines.length > 0) {
        _MarkdownInlineContainer stackList = _currentBlock.inlines.first;
        _currentBlock.inlines = stackList.children;
        _currentBlock.didFinishParsingChildren();
      } else {
        _currentBlock.inlines = <_MarkdownInline>[new _MarkdownInlineString('')];
        // TODO(abarth): Why don't we mark the block as closed here?
      }
    } else {
      if (_currentBlock.inlines.length > 1) {
        _MarkdownInlineContainer poppedList = _currentBlock.inlines.last;
        List<_MarkdownInline> popped = poppedList.children;
        _currentBlock.inlines.removeLast();

        _MarkdownInlineContainer topList = _currentBlock.inlines.last;
        List<_MarkdownInline> top = topList.children;
        top.add(new _MarkdownInlineContainer(popped));
      }
    }
  }

  static const List<String> _kBlockTags = const <String>['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'img', 'pre', 'ol', 'ul'];
  static const List<String> _kListTags = const <String>['ul', 'ol'];

  bool _isBlockTag(String tag) {
    return _kBlockTags.contains(tag);
  }

  bool _isListTag(String tag) {
    return _kListTags.contains(tag);
  }

  MarkdownBlock get _currentBlock => _currentBlockInList(_blocks);

  MarkdownBlock _currentBlockInList(List<MarkdownBlock> blocks) {
    if (blocks.isEmpty)
      return null;

    if (!blocks.last.isOpen)
      return null;

    MarkdownBlock childBlock = _currentBlockInList(blocks.last.children);
    if (childBlock != null)
      return childBlock;

    return blocks.last;
  }
}

abstract class _MarkdownInline {
  const _MarkdownInline();
}

class _MarkdownInlineContainer extends _MarkdownInline {
  const _MarkdownInlineContainer(this.children);

  final List<_MarkdownInline> children;
}

class _MarkdownInlineTextStyle extends _MarkdownInline {
  const _MarkdownInlineTextStyle(this.style, [this.linkInfo = null]);

  final TextStyle style;
  final _LinkInfo linkInfo;
}

class _MarkdownInlineString extends _MarkdownInline {
  const _MarkdownInlineString(this.string);

  final String string;
}

class _MarkdownInlineTextSpan extends _MarkdownInline {
  const _MarkdownInlineTextSpan(this.textSpan);

  final TextSpan textSpan;
}

class MarkdownObject {
  MarkdownObject({
    @required this.tag,
    @required this.attributes,
  }) {
    assert(tag != null);
    assert(attributes != null);
  }

  final String tag;
  final Map<String, String> attributes;
}

class MarkdownSpan extends MarkdownObject {
  MarkdownSpan ({
    @required String tag,
    @required Map<String, String> attributes,
    this.text,
  }) : super(tag: tag, attributes: attributes);

  final String text;

  List<MarkdownSpan> get children => _children;
  List<MarkdownSpan> _children;

  void appendChild(MarkdownSpan span) {
    _children ??= <MarkdownSpan>[];
    _children.add(span);
  }

  TextSpan build(MarkdownStyleRaw style) {
    TextStyle textStyle = style.styles[tag] ?? const TextStyle();
    return null;
  }
}

class MarkdownBlock extends MarkdownObject {
  MarkdownBlock({
    @required String tag,
    @required Map<String, String> attributes,
    this.listIndents: const <String>[],
    this.listIndex: 0,
  }) : super(tag: tag, attributes: attributes) {
//    TextStyle textStyle= style.styles[tag] ?? const TextStyle(color: const Color(0xffff0000));
//    inlines = <_MarkdownInline>[new _MarkdownInlineContainer(<_MarkdownInline>[new _MarkdownInlineTextStyle(textStyle)])];
  }

  final List<String> listIndents;
  final int listIndex;

  List<_MarkdownInline> inlines;
  final List<MarkdownBlock> children = <MarkdownBlock>[];

  bool get isOpen => _isOpen;
  bool _isOpen = true;

  void didFinishParsingChildren() {
    _isOpen = false;
    if (children.length > 0)
      children.last._isLast = true;
  }

  bool get isLast => _isLast;
  bool _isLast = false;

  Widget build(MarkdownStyleRaw style) {
    if (tag == 'img')
      return _buildImage(attributes['src']);

    final double spacing = isLast ? 0.0: style.blockSpacing;

    Widget contents;

    if (children.length > 0) {
      List<Widget> childWidgets = <Widget>[];

      for (MarkdownBlock child in children)
        childWidgets.add(child.build(style));

      contents = new Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: childWidgets,
      );
    } else {
      TextSpan span = _stackToTextSpan(new _MarkdownInlineContainer(inlines));
      contents = new RichText(text: span);

      if (listIndents.length > 0) {
        Widget bullet;
        if (listIndents.last == 'ul') {
          bullet = new Text(
              '•',
              textAlign: TextAlign.center,
          );
        }
        else {
          bullet = new Padding(
              padding: new EdgeInsets.only(right: 5.0),
              child: new Text(
                  '${listIndex + 1}.',
                  textAlign: TextAlign.right,
              )
          );
        }

        contents = new Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              new SizedBox(
                  width: listIndents.length * style.listIndent,
                  child: bullet,
              ),
              new Expanded(child: contents),
            ]
        );
      }
    }

    BoxDecoration decoration;
    EdgeInsets padding;

    if (tag == 'blockquote') {
      decoration = style.blockquoteDecoration;
      padding = new EdgeInsets.all(style.blockquotePadding);
    } else if (tag == 'pre') {
      decoration = style.codeblockDecoration;
      padding = new EdgeInsets.all(style.codeblockPadding);
    }

    return new Container(
      child: contents,
      decoration: decoration,
      padding: padding,
      margin: new EdgeInsets.only(bottom: spacing),
    );
  }

  TextSpan _stackToTextSpan(_MarkdownInline inlines) {
    if (inlines is _MarkdownInlineTextSpan)
      return inlines.textSpan;

    if (inlines is _MarkdownInlineContainer) {
      List<_MarkdownInline> list = inlines.children;
      _MarkdownInlineTextStyle styleNode = list[0];
      _LinkInfo linkInfo = styleNode.linkInfo;
      TextStyle style = styleNode.style;

      List<TextSpan> children = <TextSpan>[];
      for (int i = 1; i < list.length; i++) {
        children.add(_stackToTextSpan(list[i]));
      }

      String text;
      if (children.length == 1 && _isPlainText(children[0])) {
        text = children[0].text;
        children = null;
      }

      TapGestureRecognizer recognizer = linkInfo?.recognizer;

      return new TextSpan(style: style, children: children, recognizer: recognizer, text: text);
    }

    if (inlines is _MarkdownInlineString) {
      return new TextSpan(text: inlines.string);
    }

    return null;
  }

  bool _isPlainText(TextSpan span) {
    return (span.text != null && span.style == null && span.recognizer == null && span.children == null);
  }

  Widget _buildImage(String src) {
    List<String> parts = src.split('#');
    if (parts.length == 0) return new Container();

    String path = parts.first;
    double width;
    double height;
    if (parts.length == 2) {
      List<String> dimensions = parts.last.split('x');
      if (dimensions.length == 2) {
        width = double.parse(dimensions[0]);
        height = double.parse(dimensions[1]);
      }
    }

    return new Image.network(path, width: width, height: height);
  }
}

class _LinkInfo {
  _LinkInfo(this.href, this.recognizer);

  final String href;
  final TapGestureRecognizer recognizer;
}

class _LinkHandler {
  _LinkHandler(this.onTapLink);

  List<_LinkInfo> links = <_LinkInfo>[];
  MarkdownLinkCallback onTapLink;

  _LinkInfo createLinkInfo(String href) {
    TapGestureRecognizer recognizer = new TapGestureRecognizer();
    recognizer.onTap = () {
      if (onTapLink != null)
        onTapLink(href);
    };

    _LinkInfo linkInfo = new _LinkInfo(href, recognizer);
    links.add(linkInfo);

    return linkInfo;
  }

  void dispose() {
    for (_LinkInfo linkInfo in links) {
      linkInfo.recognizer.dispose();
    }
  }
}

abstract class SyntaxHighlighter { // ignore: one_member_abstracts
  TextSpan format(String source);
}
