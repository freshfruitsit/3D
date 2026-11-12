import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'data/catalog.dart';
import 'screens/account_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/home_screen.dart';
import 'screens/product_list_screen.dart';
import 'services/shopify_api.dart';
import 'state/cart_store.dart';
import 'state/favourites_store.dart';
import 'theme/app_theme.dart';
import 'widgets/ask_button.dart';
import 'widgets/floating_nav_bar.dart';
import 'widgets/intro_gate.dart';

export 'widgets/floating_nav_bar.dart' show AppTab;

/// Which bottom tab is showing. Screens change it through
/// `AppNav.goToTab`, not directly.
class ShellController extends ChangeNotifier {
  AppTab _tab = AppTab.home;
  int _reselects = 0;

  AppTab get tab => _tab;

  /// Goes up each time the tab that is already showing is chosen again;
  /// the shell then returns that tab to its first screen.
  int get reselects => _reselects;

  void select(AppTab tab) {
    if (tab == _tab) {
      _reselects++;
    } else {
      _tab = tab;
    }
    notifyListeners();
  }
}

/// Puts the API, the stores and the shell controller above [child].
/// The app uses it once above MaterialApp; tests use it to wrap a screen.
class AppScope extends StatelessWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.cart,
    required this.favourites,
    this.shell,
    required this.child,
  });

  final ShopifyApi api;
  final CartStore cart;
  final FavouritesStore favourites;

  /// Supply one to observe tab changes in tests; otherwise one is created.
  final ShellController? shell;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ShopifyApi>.value(value: api),
        ChangeNotifierProvider<CartStore>.value(value: cart),
        ChangeNotifierProvider<FavouritesStore>.value(value: favourites),
        if (shell != null)
          ChangeNotifierProvider<ShellController>.value(value: shell!)
        else
          ChangeNotifierProvider<ShellController>(
            create: (_) => ShellController(),
          ),
      ],
      child: child,
    );
  }
}

/// The whole app.
class FreshMarketApp extends StatelessWidget {
  const FreshMarketApp({
    super.key,
    required this.api,
    required this.cart,
    required this.favourites,
    this.shell,
  });

  final ShopifyApi api;
  final CartStore cart;
  final FavouritesStore favourites;
  final ShellController? shell;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      api: api,
      cart: cart,
      favourites: favourites,
      shell: shell,
      child: MaterialApp(
        title: 'Fresh Market',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        // First launch shows the intro video once, then the shell.
        home: const IntroGate(child: AppShell()),
      ),
    );
  }
}

/// The five tabs with the floating bottom bar.
///
/// Each tab has its own navigator, so lists and search pushed from a tab
/// keep the bar and keep that tab highlighted. Product detail and checkout
/// are pushed on the root navigator and cover the bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final Map<AppTab, GlobalKey<NavigatorState>> _navigators = {
    for (final tab in AppTab.values) tab: GlobalKey<NavigatorState>(),
  };

  /// Tabs are built the first time they are shown, so the app does not
  /// load every tab's data at launch.
  final Set<AppTab> _visited = {AppTab.home};

  ShellController? _controller;
  int _seenReselects = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ShellController>();
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onShellChanged);
      _controller = controller..addListener(_onShellChanged);
      _seenReselects = controller.reselects;
      _visited.add(controller.tab);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onShellChanged);
    super.dispose();
  }

  void _onShellChanged() {
    final controller = _controller!;
    if (controller.reselects != _seenReselects) {
      _seenReselects = controller.reselects;
      _navigators[controller.tab]!
          .currentState
          ?.popUntil((route) => route.isFirst);
    }
    setState(() => _visited.add(controller.tab));
  }

  Widget _rootOf(AppTab tab) => switch (tab) {
        AppTab.home => const HomeScreen(),
        AppTab.categories => const CategoriesScreen(),
        AppTab.deals => const ProductListScreen.collection(
            handle: Catalog.dealsHandle,
            title: Catalog.dealsTitle,
          ),
        AppTab.cart => const CartScreen(),
        AppTab.account => const AccountScreen(),
      };

  /// System back: first inside the tab, then to Home, then leave the app.
  void _onBack() {
    final controller = _controller!;
    final navigator = _navigators[controller.tab]!.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.maybePop();
    } else if (controller.tab != AppTab.home) {
      controller.select(AppTab.home);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = context.watch<ShellController>().tab;
    final cartCount = context.select<CartStore, int>((c) => c.itemCount);
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final safeBottom = media.viewPadding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: appOverlayStyle,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
        child: ColoredBox(
          color: AppColors.page,
          child: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: current.index,
                  children: [
                    for (final tab in AppTab.values)
                      if (_visited.contains(tab))
                        TickerMode(
                          enabled: tab == current,
                          child: Navigator(
                            key: _navigators[tab],
                            onGenerateRoute: (settings) =>
                                MaterialPageRoute<void>(
                              settings: settings,
                              builder: (_) => _rootOf(tab),
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                  ],
                ),
              ),
              if (!keyboardOpen) ...[
                // Soft scrim so content scrolling under the bar fades out.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: FloatingNavBar.bottomInset +
                      FloatingNavBar.height +
                      32 +
                      safeBottom,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x00DCEBDD),
                            Color(0xE6DCEBDD),
                            AppColors.page,
                          ],
                          stops: [0, 0.55, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: FloatingNavBar.bottomInset + safeBottom,
                  child: FloatingNavBar(
                    current: current,
                    cartCount: cartCount,
                    onSelected: context.read<ShellController>().select,
                  ),
                ),
                // The assistant button floats above the bar's right end and
                // hides with it. Not on Cart, where it would sit on the
                // order summary and its checkout button.
                if (current != AppTab.cart)
                  Positioned(
                    right: AppDims.gutter,
                    bottom: FloatingNavBar.bottomInset +
                        safeBottom +
                        FloatingNavBar.height +
                        AskButton.gapAboveNavBar,
                    child: const AskButton(),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
