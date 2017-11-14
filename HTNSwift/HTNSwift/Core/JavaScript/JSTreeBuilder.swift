//
//  JSTreeBuilder.swift
//  HTNSwift
//
//  Created by DaiMing on 2017/10/30.
//  Copyright © 2017年 Starming. All rights reserved.
//

import Foundation

public class JSTreeBuilder {
    var tokenizer: JSTokenizer
    public var rootNode: JSNode
    
    private var _lastToken = JSToken()
    private var _currentToken = JSToken() //当前的 token
    private var _lastNode: JSNode       //上一个节点
    private var _currentNode: JSNode    //当前节点
    private var _currentParent: JSNode? // 当前父节点
    private var _stackNode = [JSNode]()
    
    init(_ input: String) {
        tokenizer = JSTokenizer(input)
        rootNode = JSNode(type: .Root)
        _lastNode = JSNode(type: .Unknown)
        _currentNode = JSNode(type: .Unknown)
    }
    
    func parser() {
//        let combinedKeywordArray = ["*=","/=","%=","+=","-=","<<=",">>=",">>>=","&=","^=","|="]
        let tks = tokenizer.parse()
        let stateMachine = HTNStateMachine<S,E>(S.UnknownState)
        
        _currentParent = rootNode
        _stackNode.append(rootNode)
        
        let sameExpressionState = [S.StartExpressionState,S.StartRoundBracketState,S.StartBracketState,S.StartBraceState]
        let beginState = [S.UnknownState,S.StartBraceState]
        
        //--------碰到 var 需要创建新节点
        stateMachine.listen(E.VarEvent, transit: beginState, to: S.StartVarState) { (t) in
            self._currentNode = JSNode(type: .VariableStatement)
            self.parentAppendChild()
            
            self._currentNode = JSNode(type: .VariableDeclarator)
            self.parentAppendChild()
        }
        stateMachine.listen(E.CharEvent, transit: S.StartVarState, to: S.StartVarIdentifierState) { (t) in
            self._currentNode = JSNode(type: .Identifier)
            self._currentNode.data = self._currentToken.data
            self.parentAppendChild()
        }
        stateMachine.listen(E.EqualEvent, transit: S.StartVarIdentifierState, to: S.StartExpressionState) { (t) in
            self.popStackNode()
            self._currentNode = JSNode(type: .Expression)
            self.parentAppendChild()
        }
        stateMachine.listen(E.CharEvent, transit: sameExpressionState, to: S.StartExpressionState) { (t) in
            self._currentNode = JSNode(type: .Identifier)
            self._currentNode.data = self._currentToken.data
            self.parentAppendChild()
            self.popStackNode()
        }
        //处理 a.b.c
        stateMachine.listen(E.DotEvent, transit: sameExpressionState, to: S.StartExpressionState) { (t) in
            self._currentNode = JSNode(type: .Dot)
            self.parentAppendChild()
            self.popStackNode()
        }
        
        //处理 "abc"
        stateMachine.listen(E.QuotationMarkEvent, transit: sameExpressionState, to: S.StartQuotationMarkState) { (t) in
            self._currentNode = JSNode(type: .Literal)
        }
        stateMachine.listen(E.KeyWordEvent, transit: S.StartQuotationMarkState, to: S.StartQuotationMarkState) { (t) in
            if self._currentToken.data == "\"" || self._currentToken.data == "'" {
                return
            }
            self._currentNode.data += self._currentToken.data
        }
        stateMachine.listen(E.CharEvent, transit: S.StartQuotationMarkState, to: S.StartQuotationMarkState) { (t) in
            self._currentNode.data += self._currentToken.data
        }
        stateMachine.listen(E.QuotationMarkEvent, transit: S.StartQuotationMarkState, to: S.StartExpressionState) { (t) in
            self.parentAppendChild()
            self.popStackNode()
        }
        
        //处理运算符 + - * /
        stateMachine.listen(E.OperatorEvent, transit: sameExpressionState, to: S.StartExpressionState) { (t) in
            self._currentNode = JSNode(type: .Operator)
            self._currentNode.data = self._currentToken.data
            self.parentAppendChild()
            self.popStackNode()
        }
        
        //处理小括号 ()
        stateMachine.listen(E.RoundBracketLeftEvent, transit: sameExpressionState, to: S.StartRoundBracketState) { (t) in
            self._currentNode = JSNode(type: .RoundBracket)
            self.parentAppendChild()
        }
        
        stateMachine.listen(E.RoundBracketRightEvent, transit: [S.StartExpressionState,S.StartRoundBracketState,S.UnknownState], to: S.StartExpressionState) { (t) in
            self.popStackNode()
        }
        //处理中括号 {}
        stateMachine.listen(E.BraceLeftEvent, transit: sameExpressionState, to: S.StartBraceState) { (t) in
            self._currentNode = JSNode(type: .Brace)
            self.parentAppendChild()
        }
        stateMachine.listen(E.BraceRightEvent, transit: [S.StartExpressionState,S.StartBraceState,S.UnknownState], to: S.StartExpressionState) { (t) in
            self.popStackNode()
            
            if self._currentParent?.type == .FunctionExpression {
                self.popStackNode()
            }
            //var myNameArray = ['Chris', function(){var a = "d"}, 'Jim'];
            if self._currentParent?.type == .VariableDeclarator {
                self.popStackNode() //VariableStatement
                self.popStackNode() //Brace
                self.popStackNode() //FunctionExpression
                self.popStackNode() 
            }
            
        }
        //处理大括号 []
        stateMachine.listen(E.BracketLeftEvent, transit: sameExpressionState, to: S.StartBracketState) { (t) in
            self._currentNode = JSNode(type: .Bracket)
            self.parentAppendChild()
        }
        stateMachine.listen(E.BracketRightEvent, transit: [S.StartExpressionState,S.StartBracketState], to: S.StartExpressionState) { (t) in
            self.popStackNode()
        }
        
        //-------------有左表达式的
        stateMachine.listen(E.CharEvent, transit: beginState, to: S.StartExpressionState) { (t) in
            self._currentNode = JSNode(type: .LeftHandSideExpression)
            self.parentAppendChild()
            self._currentNode = JSNode(type: .Identifier)
            self._currentNode.data = self._currentToken.data
            self.parentAppendChild()
            self.popStackNode()
        }

        stateMachine.listen(E.EqualEvent, transit: S.StartExpressionState, to: S.StartExpressionState) { (t) in
            self._currentNode = JSNode(type: .Expression)
            self.parentAppendChild()
        }
        
        //处理function
        stateMachine.listen(E.FunctionEvent, transit: [S.UnknownState,S.StartExpressionState], to: S.StartExpressionState) { (t) in
            //
            self._currentNode = JSNode(type: .FunctionExpression)
            self.parentAppendChild()
        }
        
        
        //处理结束，针对不同的情况这些结束标识符需要做不同的处理
        stateMachine.listen(E.EndNodeEvent, transit: S.StartExpressionState, to: S.UnknownState) { (t) in
            self.popStackNode()
            //处理 Var 表达式
            if self._currentParent?.type == .VariableDeclarator {
                self.popStackNode()
                self.popStackNode()
            }
            //处理 LeftHandSideExpression 的情况
            if self._currentParent?.type == .LeftHandSideExpression {
                self.popStackNode()
            }
        }
        stateMachine.listen(E.CommaEvent, transit: S.StartExpressionState, to: S.StartVarState) { (t) in
            if self._currentParent?.type == .RoundBracket || self._currentParent?.type == .Bracket {
                self._currentNode = JSNode(type: .CommaSplit)
                self.parentAppendChild()
                stateMachine.changeCurrentState(S.StartExpressionState)
            }
            self.popStackNode()
            //处理 Var 表达式
            if self._currentParent?.type == .VariableDeclarator {
                self.popStackNode()
                self._currentNode = JSNode(type: .VariableDeclarator)
                self.parentAppendChild()
            }
        }
        
        _currentParent = rootNode
        for tk in tks {
            _currentToken = tk
            if tk.type == .KeyWords {
                _ = stateMachine.trigger(E.KeyWordEvent)
                //开始 JScriptVarDeclarationNode
                if tk.data == "var" {
                    _ = stateMachine.trigger(E.VarEvent)
                }
                if tk.data == "=" {
                    _ = stateMachine.trigger(E.EqualEvent)
                }
                if tk.data == "." {
                    _ = stateMachine.trigger(E.DotEvent)
                }
                if tk.data == "," {
                    _ = stateMachine.trigger(E.CommaEvent)
                }
                if tk.data == ";" || tk.data == "\n" {
                    _ = stateMachine.trigger(E.EndNodeEvent)
                }
                if tk.data == "\"" || tk.data == "'" {
                    _ = stateMachine.trigger(E.QuotationMarkEvent)
                }
                if tk.data == "[" {
                    _ = stateMachine.trigger(E.BracketLeftEvent)
                }
                if tk.data == "]" {
                    _ = stateMachine.trigger(E.BracketRightEvent)
                }
                if tk.data == "(" {
                    _ = stateMachine.trigger(E.RoundBracketLeftEvent)
                }
                if tk.data == ")" {
                    _ = stateMachine.trigger(E.RoundBracketRightEvent)
                }
                if tk.data == "{" {
                    _ = stateMachine.trigger(E.BraceLeftEvent)
                }
                if tk.data == "}" {
                    _ = stateMachine.trigger(E.BraceRightEvent)
                }
                //操作符
                if tk.data == "+" || tk.data == "-" || tk.data == "*" || tk.data == "/" {
                    _ = stateMachine.trigger(E.OperatorEvent)
                }
                //function
                if tk.data == "function" {
                    _ = stateMachine.trigger(E.FunctionEvent)
                }
            }
            if tk.type == .Char {
                _ = stateMachine.trigger(E.CharEvent)
            }
            _lastToken = tk
        }
    }
    
    //help
    func parentAppendChild() {
        _currentNode.parent = _currentParent
        _currentParent?.children.append(_currentNode)
        _currentParent = _currentNode
        _stackNode.append(_currentNode)
    }
    func popStackNode() {
        _ = _stackNode.popLast()
        _currentParent = _stackNode.last
    }
    
    enum S: HTNStateType {
        //StartVarExpressionState，StartRoundBracketState
        case UnknownState
        case StartVarState
        case StartVarIdentifierState
        case StartExpressionState      //处理相同 expression
        case StartRoundBracketState    //处理相同 expression
        case StartBracketState         //处理相同 expression
        case StartBraceState           //处理相同 expression
        case StartQuotationMarkState
        
        case StartLeftHandSideState
    }
    enum E: HTNEventType {
        //char
        case CharEvent        // char 类型
        case KeyWordEvent     // keyword 类型
        //可能会开始新 Node 的事件
        case VarEvent         // var
        case DotEvent         // .
        case CommaEvent       // ,
        case QuotationMarkEvent  // " '
        case OperatorEvent       // + - * / 操作符
        case RoundBracketLeftEvent  // (
        case RoundBracketRightEvent // )
        case BracketLeftEvent    // [
        case BracketRightEvent   // ]
        case BraceLeftEvent      // {
        case BraceRightEvent     // }
        case FunctionEvent       // function
        case ForEvent            // for
        case WhileEvent          // while
        case IfEvent             // if
        case TryEvent            // try
        case ReturnEvent         // return
        case TypeofEvent         // typeof
        
        //可能结束一个 Node 的事件
        case EndNodeEvent   // ; 或者 \n
        case EqualEvent       // =
        
    }
}
