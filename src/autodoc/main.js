(function () {
  const CAT_namespace = 0;
  const CAT_container = 1;
  const CAT_global_variable = 2;
  const CAT_function = 3;
  const CAT_primitive = 4;
  const CAT_error_set = 5;
  const CAT_global_const = 6;
  const CAT_alias = 7;
  const CAT_type = 8;
  const CAT_type_type = 9;
  const CAT_type_function = 10;
  const CAT_type_fn_instance = 11;
  const CAT_using_namespace = 12;

  const LOG_err = 0;
  const LOG_warn = 1;
  const LOG_info = 2;
  const LOG_debug = 3;

  const domDocTestsCode = orFail(document.getElementById("docTestsCode"));
  const domFnErrorsAnyError = orFail(
    document.getElementById("fnErrorsAnyError"),
  );
  const domFnProto = orFail(document.getElementById("fnProto"));
  const domFnProtoCode = orFail(document.getElementById("fnProtoCode"));
  const domHdrName = orFail(document.getElementById("hdrName"));
  const domHdrSub = orFail(document.getElementById("hdrSub"));
  const domListErrSets = orFail(document.getElementById("listErrSets"));
  const domListTocErrSets = orFail(document.getElementById("listTocErrSets"));
  const domListFields = orFail(document.getElementById("listFields"));
  // const domListTocFields = orFail(document.getElementById("listTocFields"));
  const domListParams = orFail(document.getElementById("listParams"));
  const domListFnErrors = orFail(document.getElementById("listFnErrors"));
  const domListFns = orFail(document.getElementById("listFns"));
  const domListTocFns = orFail(document.getElementById("listTocFns"));
  const domListGlobalVars = orFail(document.getElementById("listGlobalVars"));
  const domListTocGlobalVars = orFail(
    document.getElementById("listTocGlobalVars"),
  );
  const domListNamespaces = orFail(document.getElementById("listNamespaces"));
  const domListTocNamespaces = orFail(
    document.getElementById("listTocNamespaces"),
  );
  const domItemsNav = orFail(document.getElementById("n5e-nav-container"));
  const domListNav = orFail(document.getElementById("listNav"));
  const domListSearchResults = orFail(
    document.getElementById("listSearchResults"),
  );
  const domListTypes = orFail(document.getElementById("listTypes"));
  const domListTocTypes = orFail(document.getElementById("listTocTypes"));
  const domListValues = orFail(document.getElementById("listValues"));
  const domListTocValues = orFail(document.getElementById("listTocValues"));
  const domSearch = /** @type {HTMLInputElement} */ (
    orFail(document.getElementById("search"))
  );
  const domSectDocTests = orFail(document.getElementById("sectDocTests"));
  const domSectTocDocTests = orFail(document.getElementById("sectTocDocTests"));
  const domSectErrSets = orFail(document.getElementById("sectErrSets"));
  const domSectTocErrSets = orFail(document.getElementById("sectTocErrSets"));
  const domSectFields = orFail(document.getElementById("sectFields"));
  const domSectTocFields = orFail(document.getElementById("sectTocFields"));
  const domSectParams = orFail(document.getElementById("sectParams"));
  const domSectTocParams = orFail(document.getElementById("sectTocParams"));
  const domSectFnErrors = orFail(document.getElementById("sectFnErrors"));
  const domSectTocFnErrors = orFail(document.getElementById("sectTocFnErrors"));
  const domSectFns = orFail(document.getElementById("sectFns"));
  const domSectTocFns = orFail(document.getElementById("sectTocFns"));
  const domSectGlobalVars = orFail(document.getElementById("sectGlobalVars"));
  const domSectTocGlobalVars = orFail(
    document.getElementById("sectTocGlobalVars"),
  );
  const domSectNamespaces = orFail(document.getElementById("sectNamespaces"));
  const domSectTocNamespaces = orFail(
    document.getElementById("sectTocNamespaces"),
  );
  const domSectNav = orFail(document.getElementById("sectNav"));
  const domSectPageToc = orFail(document.getElementById("sectPageToc"));
  const domSectSearchNoResults = orFail(
    document.getElementById("sectSearchNoResults"),
  );
  const domSectSearchResults = orFail(
    document.getElementById("sectSearchResults"),
  );
  const domSectSource = orFail(document.getElementById("sectSource"));
  const domSectTocSource = orFail(document.getElementById("sectTocSource"));
  const domSectTypes = orFail(document.getElementById("sectTypes"));
  const domSectTocTypes = orFail(document.getElementById("sectTocTypes"));
  const domSectValues = orFail(document.getElementById("sectValues"));
  const domSectTocValues = orFail(document.getElementById("sectTocValues"));
  const domSourceText = orFail(document.getElementById("sourceText"));
  const domStatus = orFail(document.getElementById("status"));
  const domTableFnErrors = orFail(document.getElementById("tableFnErrors"));
  const domTldDocs = orFail(document.getElementById("tldDocs"));
  const domTocTldDocs = orFail(document.getElementById("tocTldDocs"));
  const domErrors = orFail(document.getElementById("errors"));
  const domErrorsText = orFail(document.getElementById("errorsText"));
  // const domErrorsTocText = orFail(document.getElementById("errorsTocText"));

  domTocTldDocs.onclick = () => {
    domHdrName.scrollIntoView({ behavior: "smooth" });
  };

  domSectTocFields.onclick = () => {
    domListFields.scrollIntoView({ behavior: "smooth" });
  };

  domSectTocParams.onclick = () => {
    domSectParams.scrollIntoView({ behavior: "smooth" });
  };

  domSectTocFnErrors.onclick = () => {
    domSectFnErrors.scrollIntoView({ behavior: "smooth" });
  };

  domSectTocSource.onclick = () => {
    domSectSource.scrollIntoView({ behavior: "smooth" });
  };

  var searchTimer = null;

  const curNav = {
    crumbs: [],
    // unsigned int: decl index
    decl: null,
    // string file name matching tarball path
    path: null,
    // 0 = home
    // 1 = decl (decl)
    // 2 = source (path)
    tag: 0,

    // when this is populated, pressing the "view source" command will
    // navigate to this hash.
    /** @type {string | null} */
    viewSourceHash: null,
  };
  var curNavSearch = "";
  var curSearchIndex = -1;
  var imFeelingLucky = false;

  // names of modules in the same order as wasm
  const moduleList = [];

  let wasm_promise = fetch("main.wasm");
  let sources_promise = fetch("sources.tar").then(function (response) {
    if (!response.ok) throw new Error("unable to download sources");
    return response.arrayBuffer();
  });
  var wasm_exports = null;

  const text_decoder = new TextDecoder();
  const text_encoder = new TextEncoder();

  WebAssembly.instantiateStreaming(wasm_promise, {
    js: {
      log(level, ptr, len) {
        const msg = decodeString(ptr, len);
        switch (level) {
          case LOG_debug:
            console.debug(msg);
            break;
          case LOG_err:
            console.error(msg);
            domErrorsText.textContent += `${msg}\n`;
            domErrors.classList.remove("hidden");
            break;
          case LOG_info:
            console.info(msg);
            break;
          case LOG_warn:
            console.warn(msg);
            break;
        }
      },
    },
  }).then(function (obj) {
    wasm_exports = obj.instance.exports;
    // @ts-ignore
    window.wasm = obj; // for debugging

    sources_promise.then(function (buffer) {
      const js_array = new Uint8Array(buffer);
      const ptr = wasm_exports.alloc(js_array.length);
      const wasm_array = new Uint8Array(
        wasm_exports.memory.buffer,
        ptr,
        js_array.length,
      );
      wasm_array.set(js_array);
      wasm_exports.unpack(ptr, js_array.length);

      updateModuleList();

      window.addEventListener("popstate", onPopState, false);
      domSearch.addEventListener("keydown", onSearchKeyDown, false);
      domSearch.addEventListener("input", onSearchChange, false);
      window.addEventListener("keydown", onWindowKeyDown, false);

      renderSidebar(0);

      onHashChange(null);
    });
  });

  function renderTitle() {
    const suffix = " - Documentation";
    if (curNavSearch.length > 0) {
      document.title = `${curNavSearch} - Search${suffix}`;
    } else if (curNav.crumbs.length > 0) {
      document.title = curNav.crumbs.join(".") + suffix;
    } else if (curNav.path != null) {
      document.title = curNav.path + suffix;
    } else {
      document.title = moduleList[0] + suffix; // Home
    }
  }

  function render() {
    domFnErrorsAnyError.classList.add("hidden");
    domFnProto.classList.add("hidden");
    domHdrName.classList.add("hidden");
    domHdrSub.classList.add("hidden");
    domSectErrSets.classList.add("hidden");
    domSectTocErrSets.classList.add("hidden");
    domSectDocTests.classList.add("hidden");
    domSectTocDocTests.classList.add("hidden");
    domSectFields.classList.add("hidden");
    domSectTocFields.classList.add("hidden");
    domSectParams.classList.add("hidden");
    domSectTocParams.classList.add("hidden");
    domSectFnErrors.classList.add("hidden");
    domSectTocFnErrors.classList.add("hidden");
    domSectFns.classList.add("hidden");
    domSectTocFns.classList.add("hidden");
    domSectGlobalVars.classList.add("hidden");
    domSectTocGlobalVars.classList.add("hidden");
    domSectNamespaces.classList.add("hidden");
    domSectTocNamespaces.classList.add("hidden");
    domSectNav.classList.add("hidden");
    domSectSearchNoResults.classList.add("hidden");
    domSectSearchResults.classList.add("hidden");
    domSectSource.classList.add("hidden");
    domSectTocSource.classList.add("hidden");
    domSectTypes.classList.add("hidden");
    domSectTocTypes.classList.add("hidden");
    domSectValues.classList.add("hidden");
    domSectTocValues.classList.add("hidden");
    domStatus.classList.add("hidden");
    domTableFnErrors.classList.add("hidden");
    domTldDocs.classList.add("hidden");
    domTocTldDocs.classList.add("hidden");
    domSectPageToc.classList.add("hidden");

    /** @type {import("highlight.js").HLJSApi} */
    const hljs = window["hljs"];

    hljs.configure({
      cssSelector: "pre>code.highlight",
    });

    renderTitle();

    if (curNavSearch !== "") return renderSearch();

    switch (curNav.tag) {
      case 0:
        return renderHome();
      case 1:
        if (curNav.decl == null) {
          return renderNotFound();
        } else {
          renderDecl(curNav.decl);
          hljs.highlightAll();
          return;
        }
      case 2:
        return renderSource(curNav.path);
      default:
        throw new Error("invalid navigation state");
    }
  }

  function renderHome() {
    if (moduleList.length == 0) {
      domStatus.textContent = "sources.tar contains no modules";
      domStatus.classList.remove("hidden");
      return;
    }
    return renderModule(0);
  }

  function renderSidebar(pkg_index) {
    const root_decl = wasm_exports.find_module_root(pkg_index);

    const members = namespaceMembers(root_decl, false).slice();
    members.sort(byDeclIndexName);

    const rootName = declIndexName(root_decl);
    const hrefPrefix = `#${rootName}.`;

    resizeDomList(
      domItemsNav,
      members.length,
      `<li>
        <a href="#">
          <span></span>
          <span></span>
        </a>
      </li>`,
    );
    for (let i = 0; i < members.length; i += 1) {
      const name = declIndexName(members[i]);
      let icon = "";
      let iconClass = "";

      const category = wasm_exports.categorize_decl(members[i], 3);
      switch (category) {
        case CAT_alias:
          icon = "A";
          iconClass = "iconAlias";
          break;

        case CAT_container:
        case CAT_type:
        case CAT_type_fn_instance:
        case CAT_type_function:
          icon = "T";
          iconClass = "iconType";
          break;

        case CAT_error_set:
          icon = "E";
          iconClass = "iconErr";
          break;

        case CAT_function:
          icon = "F";
          iconClass = "iconFn";
          break;

        case CAT_global_const:
        case CAT_global_variable:
        case CAT_primitive:
        case CAT_type_type:
          icon = "V";
          iconClass = "iconVal";
          break;

        case CAT_namespace:
          icon = "N";
          iconClass = "iconNs";
          break;

        default:
          throw new Error(`unrecognized category ${category}`);
      }

      const navLiDom = domItemsNav.children[i];
      const navADom = navLiDom.children[0];
      const iconDom = navADom.children[0];
      const labelDom = navADom.children[1];

      iconDom.textContent = icon;
      iconDom.classList.add(iconClass);
      labelDom.textContent = name;
      navADom.setAttribute("href", hrefPrefix + name);
      navADom.setAttribute("id", `nav-${rootName}-${name}`);
    }
  }

  function renderModule(pkg_index) {
    const root_decl = wasm_exports.find_module_root(pkg_index);
    return renderDecl(root_decl);
  }

  function renderDecl(decl_index, alias) {
    const category = wasm_exports.categorize_decl(decl_index, 0);
    switch (category) {
      case CAT_alias:
        return renderDecl(wasm_exports.get_aliasee(), alias || decl_index);

      case CAT_container:
      case CAT_namespace:
        return renderNamespacePage(decl_index, alias);

      case CAT_error_set:
        return renderErrorSetPage(decl_index, alias);

      case CAT_function:
        return renderFunction(decl_index, alias);

      case CAT_global_const:
      case CAT_global_variable:
      case CAT_primitive:
      case CAT_type:
      case CAT_type_type:
        return renderGlobal(decl_index, alias);

      case CAT_type_fn_instance:
      case CAT_type_function:
        return renderTypeFunction(decl_index, alias);

      default:
        throw new Error(`unrecognized category ${category}`);
    }
  }

  function renderSource(path) {
    const decl_index = findFileRoot(path);
    if (decl_index == null) return renderNotFound();

    renderNavFancy([
      {
        href: location.hash,
        name: "[src]",
      },
    ]);

    domSourceText.innerHTML = declSourceHtml(decl_index);

    domSectSource.classList.remove("hidden");
  }

  function renderDeclHeading(decl_index, alias) {
    curNav.viewSourceHash = `#src/${unwrapString(wasm_exports.decl_file_path(decl_index))}`;

    const hdrNameSpan = /** @type {HTMLElement} */ (domHdrName.children[0]);
    const srcLink = domHdrName.children[1];
    const name = unwrapString(wasm_exports.decl_name(alias || decl_index));
    const category = unwrapString(wasm_exports.decl_category_name(decl_index));
    hdrNameSpan.innerText = name;
    domHdrSub.innerText = category;
    srcLink.setAttribute("href", curNav.viewSourceHash);
    domHdrName.classList.remove("hidden");
    domHdrSub.classList.remove("hidden");

    renderTopLevelDocs(decl_index, alias);
  }

  function renderTopLevelDocs(decl_index, alias) {
    const alias_docs_html =
      alias && unwrapString(wasm_exports.decl_docs_html(alias, false));

    const tld_docs_html =
      alias_docs_html?.length > 0
        ? alias_docs_html
        : unwrapString(wasm_exports.decl_docs_html(decl_index, false));

    if (tld_docs_html.length > 0) {
      domTldDocs.innerHTML = tld_docs_html;
      domTldDocs.classList.remove("hidden");
      domTocTldDocs.classList.remove("hidden");
    }
  }

  function renderNav() {
    return renderNavFancy([]);
  }

  function renderNavFancy(list) {
    let href = "";
    for (const crumb of curNav.crumbs) {
      href = href ? `${href}.${crumb}` : `#${crumb}`;
      list.push({ href, name: crumb });
    }

    resizeDomList(domListNav, 0, '<li><a href="#"></a></li>');
    resizeDomList(domListNav, list.length, '<li><a href="#"></a></li>');

    for (let i = 0; i < list.length; i += 1) {
      const liDom = domListNav.children[i];
      const aDom = liDom.children[0];
      aDom.textContent = list[i].name;
      aDom.setAttribute("href", list[i].href);
      if (i + 1 == list.length) {
        aDom.classList.add("active");
      } else {
        aDom.classList.remove("active");
      }
    }

    domSectNav.classList.remove("hidden");
  }

  function renderNotFound() {
    domStatus.textContent = "Declaration not found.";
    domStatus.classList.remove("hidden");
  }

  function navLinkFqn(full_name) {
    return `#${full_name}`;
  }

  function resizeDomList(listDom, desiredLen, templateHtml) {
    // add the missing dom entries
    for (let i = listDom.childElementCount; i < desiredLen; i += 1) {
      listDom.insertAdjacentHTML("beforeend", templateHtml);
    }
    // remove extra dom entries
    while (desiredLen < listDom.childElementCount) {
      listDom.removeChild(listDom.lastChild);
    }
  }

  function renderErrorSetPage(decl_index, alias) {
    renderNav();
    renderDeclHeading(decl_index, alias);

    const errorSetList = declErrorSet(decl_index).slice();
    renderErrorSet(decl_index, errorSetList);
  }

  function renderErrorSet(base_decl, errorSetList) {
    if (!errorSetList || errorSetList.length === 0) return;

    domFnErrorsAnyError.classList.add("hidden");
    resizeDomList(domListFnErrors, errorSetList.length, "<div></div>");
    for (let i = 0; i < errorSetList.length; i += 1) {
      const divDom = domListFnErrors.children[i];
      const html = unwrapString(
        wasm_exports.error_html(base_decl, errorSetList[i]),
      );
      divDom.innerHTML = html;
    }
    domTableFnErrors.classList.remove("hidden");
    domSectFnErrors.classList.remove("hidden");
    domSectTocFnErrors.classList.remove("hidden");
  }

  function renderParams(decl_index) {
    // Prevent params from being emptied next time wasm calls memory.grow.
    const params = declParams(decl_index).slice();
    if (params.length !== 0) {
      resizeDomList(domListParams, params.length, "<div></div>");
      for (let i = 0; i < params.length; i += 1) {
        const divDom = domListParams.children[i];
        divDom.innerHTML = unwrapString(
          wasm_exports.decl_param_html(decl_index, params[i]),
        );
      }
      domSectParams.classList.remove("hidden");
      domSectTocParams.classList.remove("hidden");
      domSectPageToc.classList.remove("hidden");
    }
  }

  function renderTypeFunction(decl_index, alias) {
    renderNav();
    renderDeclHeading(decl_index, alias);
    renderTopLevelDocs(decl_index, alias);
    renderParams(decl_index);
    renderDocTests(decl_index);

    const members = unwrapSlice32(
      wasm_exports.type_fn_members(decl_index, false),
    ).slice();
    const fields = unwrapSlice32(
      wasm_exports.type_fn_fields(decl_index),
    ).slice();
    if (members.length !== 0 || fields.length !== 0) {
      renderNamespace(decl_index, alias, members, fields);
    } else {
      domSourceText.innerHTML = declSourceHtml(decl_index);
      domSectSource.classList.remove("hidden");
      domSectTocSource.classList.remove("hidden");
    }
  }

  function renderDocTests(decl_index) {
    const doctest_html = declDoctestHtml(decl_index);
    if (doctest_html.length > 0) {
      domDocTestsCode.innerHTML = doctest_html;
      domSectDocTests.classList.remove("hidden");
    }
  }

  function renderFunction(decl_index, alias) {
    renderNav();
    renderDeclHeading(decl_index, alias);
    renderTopLevelDocs(decl_index);
    renderParams(decl_index);
    renderDocTests(decl_index);

    domFnProtoCode.innerHTML = fnProtoHtml(decl_index, alias, null, false);
    domFnProto.classList.remove("hidden");

    const errorSetNode = fnErrorSet(decl_index);
    if (errorSetNode != null) {
      const base_decl = wasm_exports.fn_error_set_decl(
        decl_index,
        errorSetNode,
      );
      renderErrorSet(base_decl, errorSetNodeList(decl_index, errorSetNode));
    }

    domSourceText.innerHTML = declSourceHtml(decl_index);
    domSectSource.classList.remove("hidden");
    domSectTocSource.classList.remove("hidden");
  }

  function renderGlobal(decl_index, alias) {
    renderNav();
    renderDeclHeading(decl_index, alias);
    renderTopLevelDocs(decl_index);
    renderParams(decl_index);
    renderDocTests(decl_index);

    const members = namespaceMembers(decl_index, false).slice();
    const fields = declFields(decl_index).slice();
    renderNamespace(decl_index, alias, members, fields);

    domSourceText.innerHTML = declSourceHtml(decl_index);
    domSectSource.classList.remove("hidden");
    domSectTocSource.classList.remove("hidden");
  }

  function renderNamespace(base_decl, base_alias, members, fields) {
    const typesList = [];
    const namespacesList = [];
    const errSetsList = [];
    const fnsList = [];
    const varsList = [];
    const valsList = [];

    member_loop: for (let i = 0; i < members.length; i += 1) {
      let member = members[i];
      const original = member;

      while (true) {
        const member_category = wasm_exports.categorize_decl(member, 0);
        switch (member_category) {
          case CAT_namespace:
            namespacesList.push({ member, original });
            continue member_loop;

          case CAT_container:
            typesList.push({ member, original });
            continue member_loop;

          case CAT_global_variable:
            varsList.push(member);
            continue member_loop;

          case CAT_function:
            fnsList.push({ member, original });
            continue member_loop;

          case CAT_type:
          case CAT_type_fn_instance:
          case CAT_type_function:
          case CAT_type_type:
            typesList.push({ member, original });
            continue member_loop;

          case CAT_error_set:
            errSetsList.push({ member, original });
            continue member_loop;

          case CAT_global_const:
          case CAT_primitive:
            valsList.push({ member, original });
            continue member_loop;

          case CAT_alias:
            member = wasm_exports.get_aliasee();
            continue;

          case CAT_using_namespace:
            throw new Error("Unexpanded usingnamespace member returned");

          default:
            throw new Error(`unknown category: ${member_category}`);
        }
      }
    }

    typesList.sort(byDeclIndexName2);
    namespacesList.sort(byDeclIndexName2);
    errSetsList.sort(byDeclIndexName2);
    fnsList.sort(byDeclIndexName2);
    varsList.sort(byDeclIndexName);
    valsList.sort(byDeclIndexName2);

    const hrefPrefix =
      location.hash && location.hash.length > 1 ? `${location.hash}.` : "#";

    // const root_decl = wasm_exports.find_module_root(0);
    const root_decl = 0;
    let showToc = base_decl !== root_decl;

    if (typesList.length !== 0) {
      resizeDomList(
        domListTypes,
        typesList.length,
        '<li><a href="#"></a></li>',
      );
      resizeDomList(
        domListTocTypes,
        typesList.length,
        '<li><a href="#"></a></li>',
      );

      for (let i = 0; i < typesList.length; i += 1) {
        const liDom = domListTypes.children[i];
        const aDom = liDom.children[0];
        const original_decl = typesList[i].original;
        const name = declIndexName(original_decl);
        aDom.textContent = name;
        aDom.setAttribute("href", hrefPrefix + name);

        const tocLi = domListTocTypes.children[i];
        const tocA = tocLi.children[0];
        tocA.textContent = name;
        tocA.setAttribute("href", hrefPrefix + name);
      }

      domSectTypes.classList.remove("hidden");
      domSectTocTypes.classList.remove("hidden");
      showToc &&= true;
    }

    if (namespacesList.length !== 0) {
      resizeDomList(
        domListNamespaces,
        namespacesList.length,
        '<li><a href="#"></a></li>',
      );
      resizeDomList(
        domListTocNamespaces,
        namespacesList.length,
        '<li><a href="#"></a></li>',
      );

      for (let i = 0; i < namespacesList.length; i += 1) {
        const liDom = domListNamespaces.children[i];
        const aDom = liDom.children[0];
        const original_decl = namespacesList[i].original;
        const name = declIndexName(original_decl);
        aDom.textContent = name;
        aDom.setAttribute("href", hrefPrefix + name);

        const tocLi = domListTocNamespaces.children[i];
        const tocA = tocLi.children[0];
        tocA.textContent = name;
        tocA.setAttribute("href", hrefPrefix + name);
      }
      domSectNamespaces.classList.remove("hidden");
      domSectTocNamespaces.classList.remove("hidden");
      showToc &&= true;
    }

    if (errSetsList.length !== 0) {
      resizeDomList(
        domListErrSets,
        errSetsList.length,
        '<li><a href="#"></a></li>',
      );
      resizeDomList(
        domListTocErrSets,
        errSetsList.length,
        '<li><a href="#"></a></li>',
      );
      for (let i = 0; i < errSetsList.length; i += 1) {
        const liDom = domListErrSets.children[i];
        const aDom = liDom.children[0];
        const original_decl = errSetsList[i].original;
        const name = declIndexName(original_decl);
        aDom.textContent = name;
        aDom.setAttribute("href", hrefPrefix + name);

        const tocLi = domListTocErrSets.children[i];
        const tocA = tocLi.children[0];
        tocA.textContent = name;
        tocA.setAttribute("href", hrefPrefix + name);
      }
      domSectErrSets.classList.remove("hidden");
      domSectTocErrSets.classList.remove("hidden");
      showToc &&= true;
    }

    if (fnsList.length !== 0) {
      resizeDomList(
        domListFns,
        fnsList.length,
        "<div><dt><pre><code></code></pre></dt><dd></dd></div>",
      );
      resizeDomList(domListTocFns, fnsList.length, '<li><a href="#"></a></li>');

      for (let i = 0; i < fnsList.length; i += 1) {
        const decl = fnsList[i].member;
        const alias = fnsList[i].original;
        const divDom = domListFns.children[i];

        const dtDom = divDom.children[0];
        const ddDocs = divDom.children[1];
        const protoCodeDom = dtDom.children[0].children[0];

        protoCodeDom.innerHTML = fnProtoHtml(
          decl,
          alias,
          base_alias || base_decl,
          true,
        );

        const tld_docs_html = unwrapString(
          wasm_exports.decl_docs_html(decl, false),
        );
        ddDocs.innerHTML = tld_docs_html;

        const tocLi = domListTocFns.children[i];
        const tocA = tocLi.children[0];
        const name = declIndexName(alias);
        tocA.textContent = name;
        tocA.setAttribute("href", hrefPrefix + name);
      }

      domSectFns.classList.remove("hidden");
      domSectTocFns.classList.remove("hidden");
      showToc &&= true;
    }

    if (fields.length !== 0) {
      resizeDomList(domListFields, fields.length, "<div></div>");

      for (let i = 0; i < fields.length; i += 1) {
        const divDom = domListFields.children[i];
        divDom.innerHTML = unwrapString(
          wasm_exports.decl_field_html(base_decl, fields[i]),
        );
      }

      domSectFields.classList.remove("hidden");
      domSectTocFields.classList.remove("hidden");
      showToc &&= true;
    }

    if (varsList.length !== 0) {
      resizeDomList(
        domListGlobalVars,
        varsList.length,
        '<tr><td><a href="#"></a></td><td></td><td></td></tr>',
      );

      resizeDomList(
        domListTocGlobalVars,
        varsList.length,
        '<li><a href="#"></a></li>',
      );

      for (let i = 0; i < varsList.length; i += 1) {
        const decl = varsList[i];
        const trDom = domListGlobalVars.children[i];

        const tdName = trDom.children[0];
        const tdNameA = tdName.children[0];
        const tdType = trDom.children[1];
        const tdDesc = trDom.children[2];

        const name = declIndexName(decl);
        tdNameA.textContent = name;
        tdNameA.setAttribute("href", hrefPrefix + name);

        tdType.innerHTML = declTypeHtml(decl);
        tdDesc.innerHTML = declDocsHtmlShort(decl);

        const tocLi = domListTocGlobalVars.children[i];
        const tocA = tocLi.children[0];
        tocA.textContent = name;
        tocA.setAttribute("href", hrefPrefix + name);
      }

      domSectGlobalVars.classList.remove("hidden");
      domSectTocGlobalVars.classList.remove("hidden");
      showToc &&= true;
    }

    if (valsList.length !== 0) {
      resizeDomList(
        domListValues,
        valsList.length,
        `<div><div class="valueName"><a></a></div><div class="valueDetails"><dt><pre><code></code></pre></dt><dd></dd></div></div>`,
      );

      resizeDomList(
        domListTocValues,
        valsList.length,
        '<li><a href="#"></a></li>',
      );

      for (let i = 0; i < valsList.length; i += 1) {
        const decl = valsList[i].member;
        const originalDecl = valsList[i].original;
        const divDom = domListValues.children[i];

        const dtDom = divDom.children[1].children[0];
        const ddDocs = divDom.children[1].children[1];
        const protoCodeDom = dtDom.children[0].children[0];

        const typeHtml = declTypeHtml(decl);
        protoCodeDom.innerHTML = `<a></a>${typeHtml ? ": " : " "}${typeHtml}`;

        const name = declIndexName(originalDecl);
        const nameA = divDom.children[0].children[0];
        nameA.setAttribute("href", hrefPrefix + name);
        nameA.textContent = name;

        protoCodeDom.innerHTML = declSourceHtml(decl);

        const tldDocsHtml = unwrapString(
          wasm_exports.decl_docs_html(decl, false),
        );
        ddDocs.innerHTML = tldDocsHtml;

        const tocLi = domListTocValues.children[i];
        const tocA = tocLi.children[0];
        tocA.textContent = name;
        tocA.setAttribute("href", hrefPrefix + name);
      }

      domSectValues.classList.remove("hidden");
      domSectTocValues.classList.remove("hidden");
      showToc &&= true;
    }

    if (showToc) domSectPageToc.classList.remove("hidden");
  }

  function renderNamespacePage(decl_index, alias) {
    const members = namespaceMembers(decl_index, false).slice();
    const fields = declFields(decl_index).slice();

    renderNav();
    renderDeclHeading(decl_index, alias);
    renderNamespace(decl_index, alias, members, fields);
  }

  function updateCurNav(location_hash) {
    curNav.tag = 0;
    curNav.crumbs = [];
    curNav.decl = null;
    curNav.path = null;
    curNav.viewSourceHash = null;
    curNavSearch = "";

    const navElPrevious = document.querySelector("a.current");
    if (navElPrevious) navElPrevious.classList.remove("current");

    if (location_hash.length < 2 || location_hash[0] !== "#") {
      const rootDecl = wasm_exports.find_module_root(0);
      location.hash = declIndexName(rootDecl);
      return false;
    }

    const query = location_hash.substring(1);
    const qPos = query.indexOf("?");
    let nonSearchPart;
    if (qPos === -1) {
      nonSearchPart = query;
    } else {
      nonSearchPart = query.substring(0, qPos);
      curNavSearch = decodeURIComponent(query.substring(qPos + 1));
    }

    if (nonSearchPart.length === 0) {
      const rootDecl = wasm_exports.find_module_root(0);
      location.hash = declIndexName(rootDecl);
      return false;
    }

    const source_mode = nonSearchPart.startsWith("src/");
    if (source_mode) {
      curNav.tag = 2;
      curNav.path = nonSearchPart.substring(4);
      return true;
    }

    curNav.tag = 1;
    curNav.decl = findDecl(nonSearchPart);
    if (curNav) curNav.crumbs = nonSearchPart.split(".");

    if (curNav.crumbs.length > 1) {
      const navId = `nav-${curNav.crumbs[0]}-${curNav.crumbs[1]}`;
      const navEl = document.getElementById(navId);
      if (navEl) {
        navEl.classList.add("current");
        navEl.scrollIntoView({ behavior: "smooth" });
      }
    }

    return true;
  }

  function onHashChange(state) {
    history.replaceState({}, "");
    navigate(location.hash);
    if (state == null) window.scrollTo({ top: 0 });
  }

  function onPopState(ev) {
    onHashChange(ev.state);
  }

  function navigate(location_hash) {
    if (!updateCurNav(location_hash)) return;

    if (domSearch.value !== curNavSearch) {
      domSearch.value = curNavSearch;
    }

    render();

    if (imFeelingLucky) {
      imFeelingLucky = false;
      activateSelectedResult();
    }
  }

  function activateSelectedResult() {
    if (domSectSearchResults.classList.contains("hidden")) {
      return;
    }

    var liDom = domListSearchResults.children[curSearchIndex];
    if (liDom == null && domListSearchResults.children.length !== 0) {
      liDom = domListSearchResults.children[0];
    }
    if (liDom != null) {
      var aDom = liDom.children[0];
      location.href = /** @type {string} */ (aDom.getAttribute("href"));
      curSearchIndex = -1;
    }
    domSearch.blur();
  }

  function onSearchKeyDown(ev) {
    switch (ev.code) {
      case "ArrowDown":
        if (ev.shiftKey || ev.ctrlKey || ev.altKey) return;

        moveSearchCursor(1);
        ev.preventDefault();
        ev.stopPropagation();
        return;
      case "ArrowUp":
        if (ev.shiftKey || ev.ctrlKey || ev.altKey) return;

        moveSearchCursor(-1);
        ev.preventDefault();
        ev.stopPropagation();
        return;
      case "Enter":
        if (ev.shiftKey || ev.ctrlKey || ev.altKey) return;

        clearAsyncSearch();
        imFeelingLucky = true;
        location.hash = computeSearchHash();

        ev.preventDefault();
        ev.stopPropagation();
        return;
      case "Escape":
        if (ev.shiftKey || ev.ctrlKey || ev.altKey) return;

        domSearch.value = "";
        domSearch.blur();
        curSearchIndex = -1;
        ev.preventDefault();
        ev.stopPropagation();
        startSearch();
        return;
      default:
        ev.stopPropagation(); // prevent keyboard shortcuts
        return;
    }
  }

  function onSearchChange() {
    curSearchIndex = -1;
    startAsyncSearch();
  }

  function moveSearchCursor(dir) {
    if (
      curSearchIndex < 0 ||
      curSearchIndex >= domListSearchResults.children.length
    ) {
      if (dir > 0) {
        curSearchIndex = -1 + dir;
      } else if (dir < 0) {
        curSearchIndex = domListSearchResults.children.length + dir;
      }
    } else {
      curSearchIndex += dir;
    }
    if (curSearchIndex < 0) {
      curSearchIndex = 0;
    }
    if (curSearchIndex >= domListSearchResults.children.length) {
      curSearchIndex = domListSearchResults.children.length - 1;
    }
    renderSearchCursor();
  }

  function onWindowKeyDown(ev) {
    switch (ev.code) {
      case "Escape":
        if (ev.shiftKey || ev.ctrlKey || ev.altKey) return;
        break;
      case "KeyS":
        if (ev.shiftKey || ev.ctrlKey || ev.altKey) return;
        domSearch.focus();
        domSearch.select();
        ev.preventDefault();
        ev.stopPropagation();
        startAsyncSearch();
        break;
      case "KeyU":
        if (ev.shiftKey || ev.ctrlKey || ev.altKey) return;
        ev.preventDefault();
        ev.stopPropagation();
        navigateToSource();
        break;
    }
  }

  function navigateToSource() {
    if (curNav.viewSourceHash != null) {
      location.hash = curNav.viewSourceHash;
    }
  }

  function clearAsyncSearch() {
    if (searchTimer != null) {
      clearTimeout(searchTimer);
      searchTimer = null;
    }
  }

  function startAsyncSearch() {
    clearAsyncSearch();
    searchTimer = setTimeout(startSearch, 10);
  }
  function computeSearchHash() {
    // How location.hash works:
    // 1. http://example.com/     => ""
    // 2. http://example.com/#    => ""
    // 3. http://example.com/#foo => "#foo"
    // wat
    const oldWatHash = location.hash;
    const oldHash = oldWatHash.startsWith("#") ? oldWatHash : `#${oldWatHash}`;
    const parts = oldHash.split("?");
    const newPart2 = domSearch.value === "" ? "" : `?${domSearch.value}`;
    return parts[0] + newPart2;
  }
  function startSearch() {
    clearAsyncSearch();
    navigate(computeSearchHash());
  }
  function renderSearch() {
    renderNav();

    const ignoreCase = curNavSearch.toLowerCase() === curNavSearch;
    const results = executeQuery(curNavSearch, ignoreCase);

    if (results.length !== 0) {
      resizeDomList(
        domListSearchResults,
        results.length,
        '<li><a href="#"></a></li>',
      );

      for (let i = 0; i < results.length; i += 1) {
        const liDom = domListSearchResults.children[i];
        const aDom = liDom.children[0];
        const match = results[i];
        const full_name = fullyQualifiedName(match);
        aDom.textContent = full_name;
        aDom.setAttribute("href", navLinkFqn(full_name));
      }
      renderSearchCursor();

      domSectSearchResults.classList.remove("hidden");
    } else {
      domSectSearchNoResults.classList.remove("hidden");
    }
  }

  function renderSearchCursor() {
    for (let i = 0; i < domListSearchResults.children.length; i += 1) {
      var liDom = domListSearchResults.children[i];
      if (curSearchIndex === i) {
        liDom.classList.add("selected");
      } else {
        liDom.classList.remove("selected");
      }
    }
  }

  function updateModuleList() {
    moduleList.length = 0;
    for (let i = 0; ; i += 1) {
      const name = unwrapString(wasm_exports.module_name(i));
      if (name.length == 0) break;
      moduleList.push(name);
    }
  }

  function byDeclIndexName(a, b) {
    const a_name = declIndexName(a);
    const b_name = declIndexName(b);
    return a_name.localeCompare(b_name);
  }

  function byDeclIndexName2(a, b) {
    const a_name = declIndexName(a.original);
    const b_name = declIndexName(b.original);
    return a_name.localeCompare(b_name);
  }

  function decodeString(ptr, len) {
    if (len === 0) return "";
    return text_decoder.decode(
      new Uint8Array(wasm_exports.memory.buffer, ptr, len),
    );
  }

  function unwrapString(bigint) {
    const ptr = Number(bigint & 0xffffffffn);
    const len = Number(bigint >> 32n);
    return decodeString(ptr, len);
  }

  function declTypeHtml(decl_index) {
    return unwrapString(wasm_exports.decl_type_html(decl_index));
  }

  function declDocsHtmlShort(decl_index) {
    return unwrapString(wasm_exports.decl_docs_html(decl_index, true));
  }

  function fullyQualifiedName(decl_index) {
    return unwrapString(wasm_exports.decl_fqn(decl_index));
  }

  function declIndexName(decl_index) {
    return unwrapString(wasm_exports.decl_name(decl_index));
  }

  function declSourceHtml(decl_index) {
    return unwrapString(wasm_exports.decl_source_html(decl_index));
  }

  function declDoctestHtml(decl_index) {
    return unwrapString(wasm_exports.decl_doctest_html(decl_index));
  }

  function fnProtoHtml(decl_index, alias, parent, linkify_fn_name) {
    return unwrapString(
      wasm_exports.decl_fn_proto_html(
        decl_index,
        alias,
        parent,
        linkify_fn_name,
      ),
    );
  }

  function setQueryString(s) {
    const jsArray = text_encoder.encode(s);
    const len = jsArray.length;
    const ptr = wasm_exports.query_begin(len);
    const wasmArray = new Uint8Array(wasm_exports.memory.buffer, ptr, len);
    wasmArray.set(jsArray);
  }

  function executeQuery(query_string, ignore_case) {
    setQueryString(query_string);
    const ptr = wasm_exports.query_exec(ignore_case);
    const head = new Uint32Array(wasm_exports.memory.buffer, ptr, 1);
    const len = head[0];
    return new Uint32Array(wasm_exports.memory.buffer, ptr + 4, len);
  }

  function namespaceMembers(decl_index, include_private) {
    return unwrapSlice32(
      wasm_exports.namespace_members(decl_index, include_private),
    );
  }

  function declFields(decl_index) {
    return unwrapSlice32(wasm_exports.decl_fields(decl_index));
  }

  function declParams(decl_index) {
    return unwrapSlice32(wasm_exports.decl_params(decl_index));
  }

  function declErrorSet(decl_index) {
    return unwrapSlice64(wasm_exports.decl_error_set(decl_index));
  }

  function errorSetNodeList(base_decl, err_set_node) {
    return unwrapSlice64(
      wasm_exports.error_set_node_list(base_decl, err_set_node),
    );
  }

  function unwrapSlice32(bigint) {
    const ptr = Number(bigint & 0xffffffffn);
    const len = Number(bigint >> 32n);
    if (len === 0) return [];
    return new Uint32Array(wasm_exports.memory.buffer, ptr, len);
  }

  function unwrapSlice64(bigint) {
    const ptr = Number(bigint & 0xffffffffn);
    const len = Number(bigint >> 32n);
    if (len === 0) return [];
    return new BigUint64Array(wasm_exports.memory.buffer, ptr, len);
  }

  function findDecl(fqn) {
    setInputString(fqn);
    const result = wasm_exports.find_decl();
    if (result === -1) return null;
    return result;
  }

  function findFileRoot(path) {
    setInputString(path);
    const result = wasm_exports.find_file_root();
    if (result === -1) return null;
    return result;
  }

  function fnErrorSet(decl_index) {
    const result = wasm_exports.fn_error_set(decl_index);
    if (result === 0) return null;
    return result;
  }

  function setInputString(s) {
    const jsArray = text_encoder.encode(s);
    const len = jsArray.length;
    const ptr = wasm_exports.set_input_string(len);
    const wasmArray = new Uint8Array(wasm_exports.memory.buffer, ptr, len);
    wasmArray.set(jsArray);
  }
  /**
   * @template T
   * @param {T | null | undefined} o
   * @returns {T}
   */
  function orFail(o) {
    if (o === undefined || o === null) {
      throw new Error("[AssertionError] Unexpected null/undefined");
    }

    return o;
  }
})();
