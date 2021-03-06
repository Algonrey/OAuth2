//
//  OAuth2WebViewController.swift
//  OAuth2
//
//  Created by Pascal Pfiffner on 7/15/14.
//  Copyright 2014 Pascal Pfiffner
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
#if os(iOS)

import UIKit
import WebKit
#if !NO_MODULE_IMPORT
import Base
#endif


/**
A simple iOS web view controller that allows you to display the login/authorization screen.
*/
open class OAuth2WebViewController: UIViewController, WKNavigationDelegate {
	
	/// Handle to the OAuth2 instance in play, only used for debug lugging at this time.
	var oauth: OAuth2?
    var script: String?
    
	/// The URL to load on first show.
	open var startURL: URL? {
		didSet(oldURL) {
			if nil != startURL && nil == oldURL && isViewLoaded {
				load(url: startURL!)
			}
		}
	}
	
	/// The URL string to intercept and respond to.
	var interceptURLString: String? {
		didSet(oldURL) {
			if let interceptURLString = interceptURLString {
				if let url = URL(string: interceptURLString) {
					interceptComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)
				}
				else {
					oauth?.logger?.debug("OAuth2", msg: "Failed to parse URL \(interceptURLString), discarding")
					self.interceptURLString = nil
				}
			}
			else {
				interceptComponents = nil
			}
		}
	}
	var interceptComponents: URLComponents?
	
	/// Closure called when the web view gets asked to load the redirect URL, specified in `interceptURLString`. Return a Bool indicating
	/// that you've intercepted the URL.
	var onIntercept: ((URL) -> Bool)?
	
	/// Called when the web view is about to be dismissed. The Bool indicates whether the request was (user-)canceled.
	var onWillDismiss: ((_ didCancel: Bool) -> Void)?
	
	/// Assign to override the back button, shown when it's possible to go back in history. Will adjust target/action accordingly.
	open var backButton: UIBarButtonItem? {
		didSet {
			if let backButton = backButton {
				backButton.target = self
				backButton.action = #selector(OAuth2WebViewController.goBack(_:))
			}
		}
	}
	
	var showCancelButton = true
	var cancelButton: UIBarButtonItem?
	
	/// Our web view.
	var webView: WKWebView?
	
	/// An overlay view containing a spinner.
	var loadingView: UIView?
	
	init() {
		super.init(nibName: nil, bundle: nil)
	}
	
	required public init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
	
	// MARK: - View Handling
	
	override open func loadView() {
		edgesForExtendedLayout = .all
		extendedLayoutIncludesOpaqueBars = true
		automaticallyAdjustsScrollViewInsets = true
		
		super.loadView()
		view.backgroundColor = UIColor.white
		
		if showCancelButton {
			cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(OAuth2WebViewController.cancel(_:)))
			navigationItem.rightBarButtonItem = cancelButton
		}
		
		// create a web view
		let web = WKWebView()
		web.translatesAutoresizingMaskIntoConstraints = false
		web.scrollView.decelerationRate = UIScrollView.DecelerationRate.normal
		web.navigationDelegate = self
		
		view.addSubview(web)
		let views = ["web": web]
		view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[web]|", options: [], metrics: nil, views: views))
		view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[web]|", options: [], metrics: nil, views: views))
		webView = web
        
        
        if let source = self.script {
            //        let cleanSource = source.replacingOccurrences(of: "\n", with: "")
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            webView!.configuration.userContentController.addUserScript(script)
        }
        
        
	}
	
	override open func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		if let web = webView, !web.canGoBack {
			if nil != startURL {
				load(url: startURL!)
			}
			else {
				web.loadHTMLString("There is no `startURL`", baseURL: nil)
			}
		}
	}
	
	func showHideBackButton(_ show: Bool) {
		if show {
			let bb = backButton ?? UIBarButtonItem(barButtonSystemItem: .rewind, target: self, action: #selector(OAuth2WebViewController.goBack(_:)))
			navigationItem.leftBarButtonItem = bb
		}
		else {
			navigationItem.leftBarButtonItem = nil
		}
	}
	
	func showLoadingIndicator() {
		// TODO: implement
	}
	
	func hideLoadingIndicator() {
		// TODO: implement
	}
	
	func showErrorMessage(_ message: String, animated: Bool) {
		NSLog("Error: \(message)")
	}
	
	
	// MARK: - Actions
	
	open func load(url: URL) {
		let _ = webView?.load(URLRequest(url: url))
	}
	
	@objc func goBack(_ sender: AnyObject?) {
		let _ = webView?.goBack()
	}
	
	@objc func cancel(_ sender: AnyObject?) {
		dismiss(asCancel: true, animated: (nil != sender) ? true : false)
	}
	
	override open func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
		dismiss(asCancel: false, animated: flag, completion: completion)
	}
	
	func dismiss(asCancel: Bool, animated: Bool, completion: (() -> Void)? = nil) {
		webView?.stopLoading()
		
		if nil != self.onWillDismiss {
			self.onWillDismiss!(asCancel)
		}
		super.dismiss(animated: animated, completion: completion)
	}
	
	
	// MARK: - Web View Delegate
    
    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        guard let _ = webView.url?.host else {
            return
        }
        
        let authenticationMethod = challenge.protectionSpace.authenticationMethod
        if authenticationMethod == NSURLAuthenticationMethodDefault || authenticationMethod == NSURLAuthenticationMethodHTTPBasic || authenticationMethod == NSURLAuthenticationMethodHTTPDigest {
            
            let title = NSLocalizedString("Authentication required \n Please insert username and password", comment: "")
            let av = UIAlertController(title: webView.title, message: title, preferredStyle: .alert)
            av.addTextField(configurationHandler: { (textField) in
                textField.placeholder = NSLocalizedString("Username", comment: "")
                if #available(iOS 11.0, *) {
                    textField.textContentType = .username
                }
            })
            av.addTextField(configurationHandler: { (textField) in
                textField.placeholder = NSLocalizedString("Password", comment: "")
                textField.isSecureTextEntry = true
                if #available(iOS 11.0, *) {
                    textField.textContentType = .password
                }
            })
            
            av.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) in
                guard let userId = av.textFields?.first?.text else{
                    return
                }
                guard let password = av.textFields?.last?.text else {
                    return
                }
                let credential = URLCredential(user: userId, password: password, persistence: .none)
                completionHandler(.useCredential,credential)
            }))
            av.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                completionHandler(.cancelAuthenticationChallenge, nil);
            }))
            self.parent?.present(av, animated: true, completion: nil)
        }else if authenticationMethod == NSURLAuthenticationMethodServerTrust{
            // needs this handling on iOS 9
            completionHandler(.performDefaultHandling, nil);
        }else{
            completionHandler(.cancelAuthenticationChallenge, nil);
        }
        
    }
    func saveCookies() {
        
        if #available(iOS 11.0, *), webView != nil {
            webView!.getCookies(completion: { (cookies) in
                
                print("Cookies in webview: \(cookies.count)")
                for cookie in cookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                
            })
        }
    }
	
	open func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Swift.Void) {
		guard let onIntercept = onIntercept else {
			decisionHandler(.allow)
			return
		}
		let request = navigationAction.request
        
        saveCookies()
		
		// we compare the scheme and host first, then check the path (if there is any). Not sure if a simple string comparison
		// would work as there may be URL parameters attached
		if let url = request.url, url.scheme == interceptComponents?.scheme && url.host == interceptComponents?.host {
			let haveComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)
			if let hp = haveComponents?.path, let ip = interceptComponents?.path, hp == ip || ("/" == hp + ip) {
				if onIntercept(url) {
					decisionHandler(.cancel)
				}
				else {
					decisionHandler(.allow)
				}
				return
			}
		}
		decisionHandler(.allow)
	}
	
	open func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		if "file" != webView.url?.scheme {
			showLoadingIndicator()
		}
	}
	
	open func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		if let scheme = interceptComponents?.scheme, "urn" == scheme {
			if let path = interceptComponents?.path, path.hasPrefix("ietf:wg:oauth:2.0:oob") {
				if let title = webView.title, title.hasPrefix("Success ") {
					oauth?.logger?.debug("OAuth2", msg: "Creating redirect URL from document.title")
					let qry = title.replacingOccurrences(of: "Success ", with: "")
					if let url = URL(string: "http://localhost/?\(qry)") {
						_ = onIntercept?(url)
						return
					}
					oauth?.logger?.warn("OAuth2", msg: "Failed to create a URL with query parts \"\(qry)\"")
				}
			}
		}
		hideLoadingIndicator()
		showHideBackButton(webView.canGoBack)
	}
	
	open func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		if NSURLErrorDomain == error._domain && NSURLErrorCancelled == error._code {
			return
		}
		// do we still need to intercept "WebKitErrorDomain" error 102?
		
		if nil != loadingView {
			showErrorMessage(error.localizedDescription, animated: true)
		}
	}
}

/// Swift < 4.2 support
#if !(swift(>=4.2))
private extension UIScrollView {
	enum DecelerationRate {
		static let normal = UIScrollViewDecelerationRateNormal
	}
}
#endif

#endif
