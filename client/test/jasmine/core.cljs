(ns jasmine.core)

(def jasmine-it js/it)
(def jasmine-describe js/describe)
(def jasmine-expect js/expect)

(def pending js/pending)

(defn to-pass-cljs-pred []
  #js {:compare
       (fn [actual pred-str pred expected]
         (let [pass (pred actual expected)]
           #js {:pass pass
                :message (str "Expected\n  " (pr-str actual) "\nto be " pred-str "\n  " (pr-str expected))}))})

(defn check [pred-str pred actual expected]
  (-> (jasmine-expect actual) (.toPassCljsPred pred-str pred expected)))
